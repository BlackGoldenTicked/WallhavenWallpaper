import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 设置弹窗：单列滚动，全部配置自上而下铺开，改动即时生效，无侧栏切换。
struct AppSettingsView: View {
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 28) {
                WallhavenSettingsSection()
                DownloadSettingsSection()
                CacheSettingsSection()
                VideoSettingsSection()
                RotationSettingsSection()
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 480, idealHeight: 680)
    }
}

// MARK: - 通用组件

/// 行：彩色图标 + 标题/副标题 + 右侧控件，参考 Wallspace 设置弹窗行式语言。
private struct SettingsRow<Control: View>: View {
    let icon: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 12)

            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// 分区：粗体标题 + 圆角卡片包裹的行列表。
private func settingsSection(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title)
            .font(.title3.weight(.bold))

        VStack(spacing: 0) {
            rows()
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 行内分隔线：左侧让出图标列，与行内容对齐。
private func rowDivider() -> some View {
    Divider()
        .opacity(0.4)
        .padding(.leading, 56)
}

// MARK: - 分区

private struct WallhavenSettingsSection: View {
    @State private var apiKey = KeychainStore.loadAPIKey()
    @State private var status = ""
    @State private var hasError = false

    var body: some View {
        settingsSection("Wallhaven") {
            SettingsRow(
                icon: "key",
                tint: .orange,
                title: "API Key",
                subtitle: "保存在系统钥匙串，仅用于向 Wallhaven 请求内容"
            ) {
                HStack(spacing: 8) {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit(saveAPIKey)

                    Button("保存", action: saveAPIKey)
                        .buttonStyle(.borderedProminent)
                }
            }

            rowDivider()

            SettingsRow(
                icon: "link",
                tint: .blue,
                title: "获取 API Key",
                subtitle: "wallhaven.cc 账户页"
            ) {
                Link("打开账户页", destination: Self.accountURL)
            }

            if !status.isEmpty {
                rowDivider()
                SettingsStatusLabel(text: status, isError: hasError)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
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

private struct DownloadSettingsSection: View {
    @AppStorage("rootPath") private var rootPath = WallhavenService.defaultRootDirectory.path
    @AppStorage("grouping") private var grouping: DownloadGrouping = .month

    var body: some View {
        settingsSection("下载") {
            SettingsRow(
                icon: "folder",
                tint: .blue,
                title: "保存目录",
                subtitle: rootPath
            ) {
                Button("更改…", action: chooseRootDirectory)
            }
            .help(rootPath)

            rowDivider()

            SettingsRow(
                icon: "square.stack.3d.up",
                tint: .cyan,
                title: "目录分组",
                subtitle: "壁纸按所选粒度建立子文件夹，便于归档与清理"
            ) {
                Picker("目录分组", selection: $grouping) {
                    ForEach(DownloadGrouping.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
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

private struct CacheSettingsSection: View {
    @AppStorage(AppCacheSettings.cacheEnabledKey) private var cacheEnabled = true
    @AppStorage(AppCacheSettings.cacheMaxSizeMBKey) private var cacheMaxSizeMB = 1024
    @State private var usage = CacheUsage(searchBytes: 0, thumbnailBytes: 0)
    @State private var status = ""
    @State private var statusIsError = false

    var body: some View {
        settingsSection("缓存") {
            SettingsRow(
                icon: "externaldrive",
                tint: .purple,
                title: "启用缓存",
                subtitle: "搜索结果与缩略图落盘，位于 ~/Library/Caches/WallhavenWallpaper"
            ) {
                Toggle("启用缓存", isOn: $cacheEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            rowDivider()

            SettingsRow(
                icon: "gauge.with.dots.needle.67percent",
                tint: .mint,
                title: "最大容量",
                subtitle: "超出上限时按最旧优先清理"
            ) {
                Picker("最大容量", selection: $cacheMaxSizeMB) {
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                }
                .labelsHidden()
                .fixedSize()
            }

            rowDivider()

            SettingsRow(
                icon: "chart.bar",
                tint: .orange,
                title: "当前占用",
                subtitle: "已用 \(formatBytes(usage.totalBytes)) / 上限 \(formatBytes(AppCacheSettings.maxSizeBytes))（搜索 \(formatBytes(usage.searchBytes)) · 缩略图 \(formatBytes(usage.thumbnailBytes))）"
            ) {
                ProgressView(value: usageFraction)
                    .frame(width: 180)
            }

            rowDivider()

            SettingsRow(
                icon: "trash",
                tint: .red,
                title: "清理缓存",
                subtitle: "清理后相关图片会重新从网络加载"
            ) {
                HStack(spacing: 8) {
                    Button("搜索结果", action: clearSearchCache)
                    Button("缩略图", action: clearThumbnailCache)
                    Button("全部", role: .destructive, action: clearAllCache)
                }
                .controlSize(.small)
            }

            if !status.isEmpty {
                rowDivider()
                SettingsStatusLabel(text: status, isError: statusIsError)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
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

private struct VideoSettingsSection: View {
    @AppStorage("videoWallpaperPath") private var videoWallpaperPath = ""
    @AppStorage("videoWallpaperMuted") private var videoWallpaperMuted = true
    @AppStorage("videoWallpaperAllScreens") private var videoWallpaperAllScreens = false
    @AppStorage("videoWallpaperPauseInLowPower") private var videoWallpaperPauseInLowPower = true
    @State private var isRunning = false
    @State private var status = ""
    @State private var statusIsError = false

    var body: some View {
        settingsSection("动态桌面") {
            SettingsRow(
                icon: "play.rectangle",
                tint: .green,
                title: "视频文件",
                subtitle: videoWallpaperPath.isEmpty ? "支持 .mp4 / .mov，未选择" : videoName
            ) {
                Button(videoWallpaperPath.isEmpty ? "选择…" : "更换…", action: chooseVideo)
            }

            rowDivider()

            SettingsRow(
                icon: "speaker.slash",
                tint: .green,
                title: "静音播放",
                subtitle: "播放时不输出声音"
            ) {
                Toggle("静音播放", isOn: $videoWallpaperMuted)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            rowDivider()

            SettingsRow(
                icon: "display",
                tint: .blue,
                title: "默认全部屏幕",
                subtitle: "关闭时仅在当前屏幕播放"
            ) {
                Toggle("默认全部屏幕", isOn: $videoWallpaperAllScreens)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            rowDivider()

            SettingsRow(
                icon: "battery.25percent",
                tint: .yellow,
                title: "低电量模式暂停",
                subtitle: "系统进入低电量模式时暂停播放"
            ) {
                Toggle("低电量模式暂停", isOn: $videoWallpaperPauseInLowPower)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            rowDivider()

            SettingsRow(
                icon: "play.circle",
                tint: .green,
                title: "播放控制",
                subtitle: "播放窗口需“辅助功能”权限才能铺在桌面图层"
            ) {
                if isRunning {
                    Button {
                        stop()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                } else {
                    Button {
                        start()
                    } label: {
                        Label("启动", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(videoWallpaperPath.isEmpty)
                }
            }

            if !status.isEmpty {
                rowDivider()
                SettingsStatusLabel(text: status, isError: statusIsError)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .onAppear {
            isRunning = VideoWallpaperController.shared.isRunning
        }
    }

    private var videoName: String {
        URL(fileURLWithPath: videoWallpaperPath).lastPathComponent
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
    }
}

private struct RotationSettingsSection: View {
    @Query(sort: \WallpaperItem.downloadedAt, order: .reverse) private var items: [WallpaperItem]
    @AppStorage("rotationIntervalMinutes") private var rotationIntervalMinutes = 30
    @AppStorage("rotationOrder") private var rotationOrder: WallpaperRotationOrder = .random
    @AppStorage("rotationAllScreens") private var rotationAllScreens = false
    @State private var isRunning = false
    @State private var status = ""
    @State private var statusIsError = false

    var body: some View {
        settingsSection("自动换壁纸") {
            SettingsRow(
                icon: "shuffle",
                tint: .orange,
                title: "切换顺序",
                subtitle: "到达间隔后按所选顺序自动切换桌面壁纸"
            ) {
                Picker("切换顺序", selection: $rotationOrder) {
                    ForEach(WallpaperRotationOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            rowDivider()

            SettingsRow(
                icon: "timer",
                tint: .blue,
                title: "切换间隔",
                subtitle: "每隔多久自动切换一张"
            ) {
                Stepper("\(rotationIntervalMinutes) 分钟", value: $rotationIntervalMinutes, in: 1...1440)
                    .fixedSize()
            }

            rowDivider()

            SettingsRow(
                icon: "display",
                tint: .blue,
                title: "全部屏幕",
                subtitle: "关闭时仅切换当前屏幕壁纸"
            ) {
                Toggle("全部屏幕", isOn: $rotationAllScreens)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            rowDivider()

            SettingsRow(
                icon: "timer",
                tint: .green,
                title: "运行控制",
                subtitle: "本地图库可用壁纸：\(candidates.count) 张"
            ) {
                if isRunning {
                    HStack(spacing: 8) {
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
                } else {
                    Button {
                        start()
                    } label: {
                        Label("启动", systemImage: "timer")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(candidates.isEmpty)
                }
            }

            if !status.isEmpty {
                rowDivider()
                SettingsStatusLabel(text: status, isError: statusIsError)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .onAppear {
            isRunning = WallpaperRotationController.shared.isRunning
        }
    }

    private var candidates: [WallpaperRotationCandidate] {
        items.map(WallpaperRotationCandidate.init)
    }

    private var rule: WallpaperRotationRule {
        WallpaperRotationRule(
            order: rotationOrder,
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
