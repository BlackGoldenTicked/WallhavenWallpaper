import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum AppSettingsPane: String, CaseIterable, Identifiable {
    case wallhaven
    case download
    case filter
    case cache
    case video
    case rotation

    var id: Self { self }

    var title: String {
        switch self {
        case .wallhaven: "Wallhaven"
        case .download: "下载"
        case .filter: "筛选"
        case .cache: "缓存"
        case .video: "动态桌面"
        case .rotation: "自动换壁纸"
        }
    }

    var systemImage: String {
        switch self {
        case .wallhaven: "key"
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
            case .wallhaven:
                WallhavenSettingsPane()
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

private struct WallhavenSettingsPane: View {
    @State private var apiKey = KeychainStore.loadAPIKey()
    @State private var status = ""
    @State private var hasError = false

    var body: some View {
        Form {
            Section {
                LabeledContent("API Key") {
                    HStack(spacing: 8) {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)
                            .onSubmit { saveAPIKey() }

                        Button {
                            saveAPIKey()
                        } label: {
                            Label("保存", systemImage: "key.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if !status.isEmpty {
                    SettingsStatusLabel(text: status, isError: hasError)
                }
            } header: {
                Text("账户")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Key 保存在系统钥匙串，仅用于向 Wallhaven 请求内容。")
                    Link("在 Wallhaven 账户页获取 API Key", destination: Self.accountURL)
                }
            }
        }
        .settingsFormStyle()
    }

    private static let accountURL = URL(string: "https://wallhaven.cc/settings/account")!

    private func saveAPIKey() {
        do {
            try KeychainStore.saveAPIKey(apiKey)
            status = "已保存到钥匙串"
            hasError = false
        } catch {
            status = error.localizedDescription
            hasError = true
        }
    }
}

private struct DownloadSettingsPane: View {
    @AppStorage("rootPath") private var rootPath = WallhavenService.defaultRootDirectory.path
    @AppStorage("downloadCount") private var downloadCount = 24
    @AppStorage("grouping") private var grouping: DownloadGrouping = .month

    var body: some View {
        Form {
            Section {
                LabeledContent("目录") {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.blue)

                        Text(rootPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 320, alignment: .trailing)
                            .help(rootPath)

                        Button("更改…") {
                            chooseRootDirectory()
                        }
                    }
                }

                Picker("目录分组", selection: $grouping) {
                    ForEach(DownloadGrouping.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("保存")
            } footer: {
                Text("壁纸会按“\(grouping.title)”在目录下建立子文件夹，便于归档与清理。")
            }

            Section {
                LabeledContent("每页数量") {
                    HStack(spacing: 12) {
                        Slider(value: downloadCountBinding, in: 1...24, step: 1)
                            .frame(width: 240)
                        Text("\(downloadCount) 张")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            } header: {
                Text("批量下载")
            } footer: {
                Text("“下载已浏览的 N 张”按此数量从当前张往回取图，已下载过的会自动跳过。")
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

    private var downloadCountBinding: Binding<Double> {
        Binding(
            get: { Double(downloadCount) },
            set: { downloadCount = max(1, min(24, Int($0.rounded()))) }
        )
    }
}

private struct FilterSettingsPane: View {
    @AppStorage("allowNSFW") private var allowNSFW = false
    @AppStorage("blurNSFW") private var blurNSFW = true
    @AppStorage("purity") private var purity: PurityFilter = .sfw

    var body: some View {
        Form {
            Section {
                Toggle("允许 NSFW", isOn: $allowNSFW)
                    .toggleStyle(.switch)
                    .onChange(of: allowNSFW) { _, isAllowed in
                        if !isAllowed { purity = .sfw }
                    }

                if allowNSFW {
                    Toggle("Sketchy / NSFW 默认模糊", isOn: $blurNSFW)
                        .toggleStyle(.switch)
                }
            } header: {
                Text("内容")
            } footer: {
                Text("模糊只作用于缩略图，点击图上的眼睛可临时查看；关闭“允许 NSFW”后筛选会回到 SFW。")
            }
        }
        .settingsFormStyle()
    }
}

private struct VideoSettingsPane: View {
    @AppStorage("videoWallpaperPath") private var videoWallpaperPath = ""
    @AppStorage("videoWallpaperMuted") private var videoWallpaperMuted = true
    @AppStorage("videoWallpaperAllScreens") private var videoWallpaperAllScreens = false
    @AppStorage("videoWallpaperPauseInLowPower") private var videoWallpaperPauseInLowPower = true
    @State private var isRunning = false
    @State private var status = ""
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                LabeledContent("文件") {
                    HStack(spacing: 8) {
                        Text(videoName)
                            .foregroundStyle(videoWallpaperPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 300, alignment: .trailing)

                        Button(videoWallpaperPath.isEmpty ? "选择…" : "更换…") {
                            chooseVideo()
                        }
                    }
                }
            } header: {
                Text("视频")
            } footer: {
                Text("支持 .mp4 / .mov；播放窗口需“辅助功能”权限才能铺在桌面图层。")
            }

            Section {
                Toggle("静音播放", isOn: $videoWallpaperMuted)
                    .toggleStyle(.switch)
                Toggle("默认全部屏幕", isOn: $videoWallpaperAllScreens)
                    .toggleStyle(.switch)
                Toggle("低电量模式暂停", isOn: $videoWallpaperPauseInLowPower)
                    .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Spacer()

                    if !videoWallpaperPath.isEmpty, !isRunning {
                        Button {
                            start()
                        } label: {
                            Label("启动动态桌面", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if isRunning {
                        Button {
                            stop()
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                    }
                }

                if !status.isEmpty {
                    SettingsStatusLabel(text: status, isError: statusIsError)
                }
            } header: {
                Text("播放")
            }
        }
        .settingsFormStyle()
        .onAppear {
            isRunning = VideoWallpaperController.shared.isRunning
        }
    }

    private var videoName: String {
        guard !videoWallpaperPath.isEmpty else { return "未选择" }
        return URL(fileURLWithPath: videoWallpaperPath).lastPathComponent
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.title = "选择动态桌面视频"
        if !videoWallpaperPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: videoWallpaperPath).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            videoWallpaperPath = url.path
            status = "已选择 \(url.lastPathComponent)"
            statusIsError = false
        }
    }

    private func start() {
        do {
            try VideoWallpaperController.shared.start(VideoWallpaperConfiguration(
                videoURL: URL(fileURLWithPath: videoWallpaperPath),
                allScreens: videoWallpaperAllScreens,
                muted: videoWallpaperMuted,
                pauseInLowPowerMode: videoWallpaperPauseInLowPower
            ))
            isRunning = true
            status = videoWallpaperAllScreens ? "正在全部屏幕播放" : "正在当前屏幕播放"
            statusIsError = false
        } catch {
            isRunning = false
            status = error.localizedDescription
            statusIsError = true
        }
    }

    private func stop() {
        VideoWallpaperController.shared.stop()
        isRunning = false
        status = "已停止"
        statusIsError = false
    }
}

private struct CacheSettingsPane: View {
    @AppStorage(AppCacheSettings.cacheEnabledKey) private var cacheEnabled = true
    @AppStorage(AppCacheSettings.cacheMaxSizeMBKey) private var cacheMaxSizeMB = 1024
    @State private var usage = CacheUsage(searchBytes: 0, thumbnailBytes: 0)
    @State private var status = ""
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                Toggle("启用缓存", isOn: $cacheEnabled)
                    .toggleStyle(.switch)

                Picker("最大容量", selection: $cacheMaxSizeMB) {
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("策略")
            } footer: {
                Text("缓存位于 ~/Library/Caches/WallhavenWallpaper，超出上限时按最旧优先清理。")
            }

            Section {
                LabeledContent("搜索结果", value: formatBytes(usage.searchBytes))
                LabeledContent("缩略图", value: formatBytes(usage.thumbnailBytes))
                LabeledContent("总计", value: formatBytes(usage.totalBytes))

                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: usageFraction)

                    Text("已用 \(formatBytes(usage.totalBytes)) / 上限 \(formatBytes(AppCacheSettings.maxSizeBytes))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } header: {
                Text("占用")
            }

            Section {
                HStack(spacing: 8) {
                    Spacer()

                    Button("清理搜索结果") {
                        clearSearchCache()
                    }

                    Button("清理缩略图") {
                        clearThumbnailCache()
                    }

                    Button("全部清理", role: .destructive) {
                        clearAllCache()
                    }
                }
                .controlSize(.small)

                if !status.isEmpty {
                    SettingsStatusLabel(text: status, isError: statusIsError)
                }
            } header: {
                Text("清理")
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

    private var usageFraction: Double {
        let limit = Double(AppCacheSettings.maxSizeBytes)
        guard limit > 0 else { return 0 }
        return min(1, Double(usage.totalBytes) / limit)
    }

    private func clearSearchCache() {
        Task {
            do {
                try await AppCacheStore.shared.clearSearchCache()
                setStatus("已清理搜索结果缓存")
                await refreshUsage()
            } catch {
                setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func clearThumbnailCache() {
        Task {
            do {
                try await AppCacheStore.shared.clearThumbnailCache()
                setStatus("已清理缩略图缓存")
                await refreshUsage()
            } catch {
                setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func clearAllCache() {
        Task {
            do {
                try await AppCacheStore.shared.clearAll()
                setStatus("已清理全部缓存")
                await refreshUsage()
            } catch {
                setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func setStatus(_ text: String, isError: Bool = false) {
        status = text
        statusIsError = isError
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
    @Query(sort: \WallpaperItem.downloadedAt, order: .reverse) private var items: [WallpaperItem]
    @AppStorage("rotationIntervalMinutes") private var rotationIntervalMinutes = 30
    @AppStorage("rotationOrder") private var rotationOrder: WallpaperRotationOrder = .random
    @AppStorage("rotationAllScreens") private var rotationAllScreens = false
    @AppStorage("rotationRequiredTags") private var rotationRequiredTags = ""
    @AppStorage("rotationMatchAllTags") private var rotationMatchAllTags = false
    @AppStorage("rotationSFWOnly") private var rotationSFWOnly = false
    @AppStorage("rotationMinWidth") private var rotationMinWidth = 0
    @AppStorage("rotationMinHeight") private var rotationMinHeight = 0
    @State private var isRunning = false
    @State private var status = ""
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section {
                Picker("顺序", selection: $rotationOrder) {
                    ForEach(WallpaperRotationOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("间隔") {
                    Stepper("\(rotationIntervalMinutes) 分钟", value: $rotationIntervalMinutes, in: 1...1440)
                }

                Toggle("全部屏幕", isOn: $rotationAllScreens)
                    .toggleStyle(.switch)
            } header: {
                Text("顺序")
            } footer: {
                Text("到达间隔后按所选顺序自动切换桌面壁纸。")
            }

            Section {
                LabeledContent("标签规则") {
                    TextField("标签，用逗号分隔", text: $rotationRequiredTags)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                Toggle("标签需全部匹配", isOn: $rotationMatchAllTags)
                    .toggleStyle(.switch)
                Toggle("仅 SFW", isOn: $rotationSFWOnly)
                    .toggleStyle(.switch)

                LabeledContent("最小宽度") {
                    Stepper("\(rotationMinWidth) px", value: $rotationMinWidth, in: 0...10000, step: 100)
                }

                LabeledContent("最小高度") {
                    Stepper("\(rotationMinHeight) px", value: $rotationMinHeight, in: 0...10000, step: 100)
                }
            } header: {
                Text("规则")
            } footer: {
                Text("本地图库可用壁纸：\(candidates.count) 张；宽高填 0 表示不限制。")
            }

            Section {
                if candidates.isEmpty {
                    Label("本地图库暂无可用壁纸", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Spacer()

                        if !isRunning {
                            Button {
                                start()
                            } label: {
                                Label("启动自动更换", systemImage: "timer")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if isRunning {
                            Button {
                                rotateNow()
                            } label: {
                                Label("下一张", systemImage: "forward.fill")
                            }

                            Button {
                                stop()
                            } label: {
                                Label("停止", systemImage: "stop.fill")
                            }
                        }
                    }
                }

                if !status.isEmpty {
                    SettingsStatusLabel(text: status, isError: statusIsError)
                }
            } header: {
                Text("运行")
            }
        }
        .settingsFormStyle()
        .onAppear {
            isRunning = WallpaperRotationController.shared.isRunning
        }
    }

    private var candidates: [WallpaperRotationCandidate] {
        items.compactMap(WallpaperRotationCandidate.init)
    }

    private var rule: WallpaperRotationRule {
        WallpaperRotationRule(
            order: rotationOrder,
            requiredTags: rotationRequiredTags,
            matchAllTags: rotationMatchAllTags,
            sfwOnly: rotationSFWOnly,
            minWidth: rotationMinWidth,
            minHeight: rotationMinHeight,
            allScreens: rotationAllScreens,
            intervalMinutes: rotationIntervalMinutes
        )
    }

    private func start() {
        do {
            try WallpaperRotationController.shared.start(candidates: candidates, rule: rule)
            isRunning = true
            status = "自动更换已启动"
            statusIsError = false
        } catch {
            isRunning = false
            status = error.localizedDescription
            statusIsError = true
        }
    }

    private func rotateNow() {
        do {
            try WallpaperRotationController.shared.rotateNow()
            status = "已切换到下一张"
            statusIsError = false
        } catch {
            status = error.localizedDescription
            statusIsError = true
        }
    }

    private func stop() {
        WallpaperRotationController.shared.stop()
        isRunning = false
        status = "已停止"
        statusIsError = false
    }
}

/// 设置页统一的行内状态提示，成功与失败用图标区分。
private struct SettingsStatusLabel: View {
    let text: String
    var isError: Bool = false

    var body: some View {
        Label(text, systemImage: isError ? "exclamationmark.triangle" : "checkmark.circle")
            .font(.caption)
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .lineLimit(2)
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
