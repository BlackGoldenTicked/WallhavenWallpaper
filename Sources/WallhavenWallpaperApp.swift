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
        .modelContainer(for: WallpaperItem.self)

        Settings {
            AppSettingsView()
                .appShaderEffect()
        }
        .modelContainer(for: WallpaperItem.self)
    }
}
