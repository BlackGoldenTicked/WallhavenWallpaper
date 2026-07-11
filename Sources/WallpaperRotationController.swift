import AppKit
import Foundation

struct WallpaperRotationCandidate: Identifiable {
    let id: String
    let fileURL: URL
    let tags: [String]
    let purity: String
    let width: Int
    let height: Int
    let downloadedAt: Date

    init?(_ item: WallpaperItem) {
        let parts = item.resolution.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else {
            return nil
        }

        self.id = item.wallhavenID
        self.fileURL = item.fileURL
        self.tags = item.tags.map { $0.lowercased() }
        self.purity = item.purity.lowercased()
        self.width = width
        self.height = height
        self.downloadedAt = item.downloadedAt
    }
}

struct WallpaperRotationRule {
    var order: WallpaperRotationOrder
    var requiredTags: String
    var matchAllTags: Bool
    var sfwOnly: Bool
    var minWidth: Int
    var minHeight: Int
    var allScreens: Bool
    var intervalMinutes: Int

    var interval: TimeInterval {
        TimeInterval(max(1, intervalMinutes) * 60)
    }
}

enum WallpaperRotationError: LocalizedError {
    case noCandidates
    case noScreen

    var errorDescription: String? {
        switch self {
        case .noCandidates: "没有符合规则的本地壁纸"
        case .noScreen: "找不到可用屏幕"
        }
    }
}

@MainActor
final class WallpaperRotationController {
    static let shared = WallpaperRotationController()

    private var timer: Timer?
    private var candidates: [WallpaperRotationCandidate] = []
    private var rule: WallpaperRotationRule?
    private var currentIndex = -1
    private var lastID: String?

    var isRunning: Bool {
        timer != nil
    }

    private init() {}

    func start(candidates: [WallpaperRotationCandidate], rule: WallpaperRotationRule) throws {
        stop()
        self.candidates = candidates
        self.rule = rule
        try rotateNow()

        let timer = Timer(timeInterval: rule.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                try? self?.rotateNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        candidates.removeAll()
        rule = nil
        currentIndex = -1
        lastID = nil
    }

    func rotateNow() throws {
        guard let rule else { throw WallpaperRotationError.noCandidates }
        let filtered = filteredCandidates(from: candidates, rule: rule)
        guard let next = nextCandidate(from: filtered, order: rule.order) else {
            throw WallpaperRotationError.noCandidates
        }
        try setWallpaper(next.fileURL, allScreens: rule.allScreens)
        lastID = next.id
    }

    private func filteredCandidates(
        from candidates: [WallpaperRotationCandidate],
        rule: WallpaperRotationRule
    ) -> [WallpaperRotationCandidate] {
        let requiredTags = rule.requiredTags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        return candidates.filter { candidate in
            guard FileManager.default.fileExists(atPath: candidate.fileURL.path) else { return false }
            if rule.sfwOnly && candidate.purity != "sfw" { return false }
            if rule.minWidth > 0 && candidate.width < rule.minWidth { return false }
            if rule.minHeight > 0 && candidate.height < rule.minHeight { return false }
            guard !requiredTags.isEmpty else { return true }

            if rule.matchAllTags {
                return requiredTags.allSatisfy { candidate.tags.contains($0) }
            } else {
                return requiredTags.contains { candidate.tags.contains($0) }
            }
        }
    }

    private func nextCandidate(
        from candidates: [WallpaperRotationCandidate],
        order: WallpaperRotationOrder
    ) -> WallpaperRotationCandidate? {
        guard !candidates.isEmpty else { return nil }

        switch order {
        case .random:
            guard candidates.count > 1 else { return candidates.first }
            var next = candidates.randomElement()
            while next?.id == lastID {
                next = candidates.randomElement()
            }
            return next
        case .sequential, .newestFirst:
            return nextInSequence(candidates.sorted { $0.downloadedAt > $1.downloadedAt })
        case .reverse, .oldestFirst:
            return nextInSequence(candidates.sorted { $0.downloadedAt < $1.downloadedAt })
        }
    }

    private func nextInSequence(_ candidates: [WallpaperRotationCandidate]) -> WallpaperRotationCandidate? {
        guard !candidates.isEmpty else { return nil }
        if let lastID,
           let index = candidates.firstIndex(where: { $0.id == lastID }) {
            currentIndex = (index + 1) % candidates.count
        } else {
            currentIndex = (currentIndex + 1) % candidates.count
        }
        return candidates[currentIndex]
    }

    private func setWallpaper(_ fileURL: URL, allScreens: Bool) throws {
        let screens = allScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        guard !screens.isEmpty else { throw WallpaperRotationError.noScreen }
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen)
        }
    }
}
