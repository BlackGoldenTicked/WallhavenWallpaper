import AppKit
import SwiftUI

private final class WallpaperWallWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class WallpaperWallWindowController: NSObject, NSWindowDelegate {
    static let shared = WallpaperWallWindowController()

    private var window: NSWindow?

    func owns(_ candidate: NSWindow?) -> Bool {
        guard let candidate, let window else { return false }
        return candidate === window
    }

    func show<Content: View>(rootView: Content) {
        close()

        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = WallpaperWallWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.level = .screenSaver
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: rootView
            .frame(width: frame.width, height: frame.height)
            .background(Color.black)
        )
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func close() {
        window?.contentView = nil
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
