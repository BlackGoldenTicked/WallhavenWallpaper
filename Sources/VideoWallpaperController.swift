import AppKit
import AVFoundation
import QuartzCore

struct VideoWallpaperConfiguration {
    let videoURL: URL
    let allScreens: Bool
    let muted: Bool
    let pauseInLowPowerMode: Bool
}

enum VideoWallpaperError: LocalizedError {
    case missingFile
    case noScreen

    var errorDescription: String? {
        switch self {
        case .missingFile: "视频文件不存在"
        case .noScreen: "找不到可用屏幕"
        }
    }
}

@MainActor
final class VideoWallpaperController {
    static let shared = VideoWallpaperController()

    private struct Session {
        let window: NSWindow
        let player: AVQueuePlayer
        let looper: AVPlayerLooper
    }

    private var sessions: [Session] = []
    private var configuration: VideoWallpaperConfiguration?
    private var observers: [NSObjectProtocol] = []

    var isRunning: Bool {
        !sessions.isEmpty
    }

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildForCurrentScreens() }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("NSProcessInfoPowerStateDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPowerState() }
        })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        })

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPowerState() }
        })
    }

    func start(_ configuration: VideoWallpaperConfiguration) throws {
        guard FileManager.default.fileExists(atPath: configuration.videoURL.path) else {
            throw VideoWallpaperError.missingFile
        }

        stop()
        self.configuration = configuration

        let targetScreens = screens(allScreens: configuration.allScreens)
        guard !targetScreens.isEmpty else { throw VideoWallpaperError.noScreen }

        sessions = targetScreens.map { screen in
            makeSession(screen: screen, configuration: configuration)
        }
        applyPowerState()
    }

    func stop() {
        for session in sessions {
            session.player.pause()
            session.window.orderOut(nil)
            session.window.close()
        }
        sessions.removeAll()
        configuration = nil
    }

    func pause() {
        sessions.forEach { $0.player.pause() }
    }

    func resume() {
        sessions.forEach { $0.player.play() }
    }

    private func rebuildForCurrentScreens() {
        guard let configuration, !sessions.isEmpty else { return }
        do {
            try start(configuration)
        } catch {
            stop()
        }
    }

    private func applyPowerState() {
        guard let configuration else { return }
        if configuration.pauseInLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled {
            pause()
        } else {
            resume()
        }
    }

    private func screens(allScreens: Bool) -> [NSScreen] {
        if allScreens {
            return NSScreen.screens
        }
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return [screen]
        }
        return NSScreen.main.map { [$0] } ?? []
    }

    private func makeSession(screen: NSScreen, configuration: VideoWallpaperConfiguration) -> Session {
        let player = AVQueuePlayer()
        player.isMuted = configuration.muted
        player.actionAtItemEnd = .none
        player.allowsExternalPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false

        let item = AVPlayerItem(url: configuration.videoURL)
        item.preferredForwardBufferDuration = 1
        let looper = AVPlayerLooper(player: player, templateItem: item)

        let view = VideoWallpaperView(player: player)
        let window = VideoWallpaperWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle
        ]
        window.orderFrontRegardless()

        return Session(window: window, player: player, looper: looper)
    }
}

final class VideoWallpaperWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class VideoWallpaperView: NSView {
    private let playerLayer = AVPlayerLayer()

    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.drawsAsynchronously = true
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
