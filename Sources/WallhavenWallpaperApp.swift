import SwiftData
import SwiftUI

@main
struct WallhavenWallpaperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .appShaderEffect()
                .frame(minWidth: 880, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 820)
        // 隐藏标题栏让舞台铺满整窗，红绿灯与顶栏悬浮在图上（Wallspace 式）。
        .windowStyle(.hiddenTitleBar)
        .modelContainer(for: WallpaperItem.self)

        Settings {
            AppSettingsView()
                .appShaderEffect()
        }
        .modelContainer(for: WallpaperItem.self)
    }
}
