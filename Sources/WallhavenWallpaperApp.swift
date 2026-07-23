import SwiftData
import SwiftUI

@main
struct WallhavenWallpaperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .appShaderEffect()
                .frame(minWidth: 720, minHeight: 560)
        }
        .modelContainer(for: WallpaperItem.self)
        .windowStyle(.hiddenTitleBar)

        Settings {
            AppSettingsView()
                .appShaderEffect()
        }
    }
}
