import AppKit
import SwiftUI

enum AppSettingsPane: String, CaseIterable, Identifiable {
    case download
    case filter
    case cache
    case video
    case rotation

    var id: Self { self }

    var title: String {
        switch self {
        case .download: "下载"
        case .filter: "筛选"
        case .cache: "缓存"
        case .video: "动态桌面"
        case .rotation: "自动换壁纸"
        }
    }

    var systemImage: String {
        switch self {
        case .download: "arrow.down.circle"
        case .filter: "line.3.horizontal.decrease.circle"
        case .cache: "externaldrive"
        case .video: "play.rectangle"
        case .rotation: "timer"
        }
    }
}

struct AppSettingsView: View {
    @State private var selectedPane: AppSettingsPane? = .download

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selectedPane) {
                ForEach(AppSettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .scrollEdgeEffectStyleSoftIfAvailable()
            .navigationTitle("设置")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            AppSettingsDetailView(pane: selectedPane ?? .download)
        }
        .navigationTitle("设置")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 500)
    }
}

private struct AppSettingsDetailView: View {
    let pane: AppSettingsPane

    var body: some View {
        Group {
            switch pane {
            case .download:
                DownloadSettingsPane()
            case .filter:
                FilterSettingsPane()
            case .cache:
                CacheSettingsPane()
            case .video:
                VideoSettingsPane()
            case .rotation:
                RotationSettingsPane()
            }
        }
        .navigationTitle(pane.title)
    }
}

private struct DownloadSettingsPane: View {
    @AppStorage("rootPath") private var rootPath = WallhavenService.defaultRootDirectory.path
    @AppStorage("downloadCount") private var downloadCount = 24

    var body: some View {
        Form {
            Section("保存") {
                LabeledContent("目录") {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)
                        Text(rootPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Button {
                    chooseRootDirectory()
                } label: {
                    Label("选择目录", systemImage: "folder")
                }
                .controlSize(.small)
            }

            Section("批量下载") {
                Stepper("每页下载数量：\(downloadCount)", value: $downloadCount, in: 1...24)
            }
        }
        .settingsFormStyle()
    }

    private func chooseRootDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: rootPath)
        panel.title = "选择壁纸保存目录"
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
        }
    }
}

private struct FilterSettingsPane: View {
    @AppStorage("allowNSFW") private var allowNSFW = false
    @AppStorage("blurNSFW") private var blurNSFW = true
    @AppStorage("resolution") private var resolution = "1920x1080"
    @AppStorage("ratios") private var ratios = "16x9,16x10"

    var body: some View {
        Form {
            Section("内容") {
                Toggle("允许 NSFW", isOn: $allowNSFW)
                    .toggleStyle(.switch)
                Toggle("NSFW 默认模糊", isOn: $blurNSFW)
                    .toggleStyle(.switch)
                    .disabled(!allowNSFW)
            }

            Section("默认筛选") {
                TextField("默认分辨率", text: $resolution)
                TextField("默认比例", text: $ratios)
            }
        }
        .settingsFormStyle()
    }
}

private struct VideoSettingsPane: View {
    @AppStorage("videoWallpaperMuted") private var videoWallpaperMuted = true
    @AppStorage("videoWallpaperAllScreens") private var videoWallpaperAllScreens = false
    @AppStorage("videoWallpaperPauseInLowPower") private var videoWallpaperPauseInLowPower = true

    var body: some View {
        Form {
            Section("播放") {
                Toggle("静音播放", isOn: $videoWallpaperMuted)
                    .toggleStyle(.switch)
                Toggle("默认全部屏幕", isOn: $videoWallpaperAllScreens)
                    .toggleStyle(.switch)
                Toggle("低电量模式暂停", isOn: $videoWallpaperPauseInLowPower)
                    .toggleStyle(.switch)
            }
        }
        .settingsFormStyle()
    }
}

private struct CacheSettingsPane: View {
    @AppStorage(AppCacheSettings.cacheEnabledKey) private var cacheEnabled = true
    @AppStorage(AppCacheSettings.cacheMaxSizeMBKey) private var cacheMaxSizeMB = 1024
    @State private var usage = CacheUsage(searchBytes: 0, thumbnailBytes: 0)
    @State private var status = ""

    var body: some View {
        Form {
            Section("策略") {
                Toggle("启用缓存", isOn: $cacheEnabled)
                    .toggleStyle(.switch)

                Picker("最大容量", selection: $cacheMaxSizeMB) {
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                }
                .pickerStyle(.segmented)
            }

            Section("占用") {
                LabeledContent("搜索结果", value: formatBytes(usage.searchBytes))
                LabeledContent("缩略图", value: formatBytes(usage.thumbnailBytes))
                LabeledContent("总计", value: formatBytes(usage.totalBytes))
            }

            Section("清理") {
                HStack(spacing: 8) {
                    Button("清理搜索结果") {
                        clearSearchCache()
                    }
                    .controlSize(.small)

                    Button("清理缩略图") {
                        clearThumbnailCache()
                    }
                    .controlSize(.small)

                    Button("全部清理", role: .destructive) {
                        clearAllCache()
                    }
                    .controlSize(.small)
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .settingsFormStyle()
        .task {
            await refreshUsage()
        }
        .onChange(of: cacheMaxSizeMB) { _, _ in
            Task { await refreshUsage() }
        }
    }

    private func clearSearchCache() {
        Task {
            do {
                try await AppCacheStore.shared.clearSearchCache()
                status = "已清理搜索结果缓存"
                await refreshUsage()
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func clearThumbnailCache() {
        Task {
            do {
                try await AppCacheStore.shared.clearThumbnailCache()
                status = "已清理缩略图缓存"
                await refreshUsage()
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func clearAllCache() {
        Task {
            do {
                try await AppCacheStore.shared.clearAll()
                status = "已清理全部缓存"
                await refreshUsage()
            } catch {
                status = error.localizedDescription
            }
        }
    }

    @MainActor
    private func refreshUsage() async {
        usage = await AppCacheStore.shared.usage()
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct RotationSettingsPane: View {
    @AppStorage("rotationIntervalMinutes") private var rotationIntervalMinutes = 30
    @AppStorage("rotationOrder") private var rotationOrder: WallpaperRotationOrder = .random
    @AppStorage("rotationAllScreens") private var rotationAllScreens = false
    @AppStorage("rotationRequiredTags") private var rotationRequiredTags = ""
    @AppStorage("rotationMatchAllTags") private var rotationMatchAllTags = false
    @AppStorage("rotationSFWOnly") private var rotationSFWOnly = false
    @AppStorage("rotationMinWidth") private var rotationMinWidth = 0
    @AppStorage("rotationMinHeight") private var rotationMinHeight = 0

    var body: some View {
        Form {
            Section("顺序") {
                Picker("顺序", selection: $rotationOrder) {
                    ForEach(WallpaperRotationOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.menu)

                Stepper("间隔：\(rotationIntervalMinutes) 分钟", value: $rotationIntervalMinutes, in: 1...1440)
                Toggle("全部屏幕", isOn: $rotationAllScreens)
                    .toggleStyle(.switch)
            }

            Section("规则") {
                TextField("标签规则", text: $rotationRequiredTags)
                Toggle("标签需全部匹配", isOn: $rotationMatchAllTags)
                    .toggleStyle(.switch)
                Toggle("仅 SFW", isOn: $rotationSFWOnly)
                    .toggleStyle(.switch)
                Stepper("最小宽度：\(rotationMinWidth)", value: $rotationMinWidth, in: 0...10000, step: 100)
                Stepper("最小高度：\(rotationMinHeight)", value: $rotationMinHeight, in: 0...10000, step: 100)
            }
        }
        .settingsFormStyle()
    }
}

private extension View {
    func settingsFormStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }

    @ViewBuilder
    func scrollEdgeEffectStyleSoftIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }
}
