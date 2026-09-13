import SwiftData
import SwiftUI

@main
struct WallhavenWallpaperApp: App {
    /// 启动首窗是否已居中：只约束启动行为，之后新建窗口保持系统默认位置。
    private static var hasCenteredFirstWindow = false

    /// 黄金比例窗口：主屏宽高的 0.618，用作窗口最小宽高。
    private var goldenWindowSize: CGSize {
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: (screen.width * 0.618).rounded(.down),
                      height: (screen.height * 0.618).rounded(.down))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appShaderEffect()
                // 浏览舞台是暗色玻璃语言，强制暗色保证胶囊/面板材质观感统一。
                .preferredColorScheme(.dark)
                .frame(minWidth: goldenWindowSize.width, minHeight: goldenWindowSize.height)
                .onAppear(perform: centerFirstWindow)
        }
        // 启动尺寸小于黄金最小值时会被最小宽高自动钳制。
        .defaultSize(width: 1280, height: 820)
        // 隐藏标题栏让舞台铺满整窗，红绿灯与顶栏悬浮在图上（Wallspace 式）。
        .windowStyle(.hiddenTitleBar)
        .modelContainer(for: WallpaperItem.self)

        Settings {
            AppSettingsView()
                .appShaderEffect()
                // 与在线/本地浏览页同款暗色风格，不随系统浅色外观切换。
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: WallpaperItem.self)
    }

    /// 启动时把首窗居中一次；异步等窗口完成恢复帧与布局，避免居中结果被覆盖。
    private func centerFirstWindow() {
        guard !Self.hasCenteredFirstWindow else { return }
        Self.hasCenteredFirstWindow = true
        DispatchQueue.main.async {
            let window = NSApplication.shared.windows.first(where: \.isMainWindow)
                ?? NSApplication.shared.windows.first(where: \.isVisible)
            window?.center()
        }
    }
}
