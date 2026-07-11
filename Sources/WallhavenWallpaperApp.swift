import SwiftData
import SwiftUI

@main
struct WallhavenWallpaperApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 560)
        }
        .modelContainer(for: WallpaperItem.self)
        .windowStyle(.hiddenTitleBar)

        Settings {
            AppSettingsView()
        }
    }
}
