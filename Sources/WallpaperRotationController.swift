import AppKit
import Foundation

struct WallpaperRotationCandidate: Identifiable {
    let id: String
    let fileURL: URL
    let downloadedAt: Date

    init(_ item: WallpaperItem) {
        self.id = item.wallhavenID
        self.fileURL = item.fileURL
        self.downloadedAt = item.downloadedAt
    }
}

struct WallpaperRotationRule {
    var order: WallpaperRotationOrder
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
        case .noCandidates: "没有可用的本地壁纸"
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
        // 只剔除文件已不存在的条目，不再做自定义规则过滤。
        let available = candidates.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        guard let next = nextCandidate(from: available, order: rule.order) else {
            throw WallpaperRotationError.noCandidates
        }
        try setWallpaper(next.fileURL, allScreens: rule.allScreens)
        lastID = next.id
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
