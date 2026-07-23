import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WallpaperItem.downloadedAt, order: .reverse) private var items: [WallpaperItem]

    @AppStorage("listing") private var listing: WallhavenListing = .latest
    @State private var query = ""
    @AppStorage("grouping") private var grouping: DownloadGrouping = .month
    @AppStorage("includeGeneral") private var includeGeneral = true
    @AppStorage("includeAnime") private var includeAnime = true
    @AppStorage("includePeople") private var includePeople = false
    @AppStorage("purity") private var purity: PurityFilter = .sfw
    @AppStorage("allowNSFW") private var allowNSFW = false
    @AppStorage("blurNSFW") private var blurNSFW = true
    @AppStorage("sorting") private var sorting: WallhavenSorting = .dateAdded
    @AppStorage("orderDescending") private var orderDescending = true
    @AppStorage("topRange") private var topRange: TopRange = .oneMonth
    @AppStorage("resolutionMode") private var resolutionMode: ResolutionMode = .atLeast
    @AppStorage("resolution") private var resolution = "1920x1080"
    @AppStorage("ratios") private var ratios = "16x9,16x10"
    @AppStorage("color") private var color = ""
    @State private var apiKey = KeychainStore.loadAPIKey()
    @AppStorage("downloadCount") private var downloadCount = 24
    @AppStorage("rootPath") private var rootPath = WallhavenService.defaultRootDirectory.path
    @AppStorage("videoWallpaperPath") private var videoWallpaperPath = ""
    @AppStorage("videoWallpaperMuted") private var videoWallpaperMuted = true
    @AppStorage("videoWallpaperAllScreens") private var videoWallpaperAllScreens = false
    @AppStorage("videoWallpaperPauseInLowPower") private var videoWallpaperPauseInLowPower = true
    @AppStorage("rotationIntervalMinutes") private var rotationIntervalMinutes = 30
    @AppStorage("rotationOrder") private var rotationOrder: WallpaperRotationOrder = .random
    @AppStorage("rotationAllScreens") private var rotationAllScreens = false
    @AppStorage("rotationRequiredTags") private var rotationRequiredTags = ""
    @AppStorage("rotationMatchAllTags") private var rotationMatchAllTags = false
    @AppStorage("rotationSFWOnly") private var rotationSFWOnly = false
    @AppStorage("rotationMinWidth") private var rotationMinWidth = 0
    @AppStorage("rotationMinHeight") private var rotationMinHeight = 0
    @State private var tagFilter = ""
    @State private var selectedID: String?
    @State private var onlineImages: [WallhavenImage] = []
    @State private var currentPage = 1
    @State private var lastPage = 1
    @State private var totalCount = 0
    @State private var randomSeed: String?
    @State private var mainMode: MainPaneMode = .online
    @State private var showSidebar = true
    @State private var showInspector = false
    @State private var showOnlineFilters = false
    @State private var isLoading = false
    @State private var isVideoWallpaperRunning = false
    @State private var isRotationRunning = false
    @State private var statusText = "就绪"
    @State private var errorMessage: String?
    @State private var pendingDeleteID: String?

    private let service = WallhavenService()
    private let resolutionOptions: [FilterOption] = [
        .init(title: "不限", value: ""),
        .init(title: "HD 1280x720", value: "1280x720"),
        .init(title: "FHD 1920x1080", value: "1920x1080"),
        .init(title: "WUXGA 1920x1200", value: "1920x1200"),
        .init(title: "QHD 2560x1440", value: "2560x1440"),
        .init(title: "WQXGA 2560x1600", value: "2560x1600"),
        .init(title: "UWQHD 3440x1440", value: "3440x1440"),
        .init(title: "4K 3840x2160", value: "3840x2160"),
        .init(title: "4K 16:10", value: "3840x2400"),
        .init(title: "竖屏 1080x1920", value: "1080x1920"),
        .init(title: "竖屏 1440x2560", value: "1440x2560")
    ]
    private let ratioOptions: [FilterOption] = [
        .init(title: "不限", value: ""),
        .init(title: "16:9", value: "16x9"),
        .init(title: "16:10", value: "16x10"),
        .init(title: "21:9", value: "21x9"),
        .init(title: "32:9", value: "32x9"),
        .init(title: "4:3", value: "4x3"),
        .init(title: "5:4", value: "5x4"),
        .init(title: "1:1", value: "1x1"),
        .init(title: "9:16", value: "9x16"),
        .init(title: "10:16", value: "10x16")
    ]
    private let wallhavenColorOptions: [WallhavenColorOption] = [
        .init(name: "红", value: "cc0000"), .init(name: "粉", value: "ea4c88"),
        .init(name: "紫", value: "993399"), .init(name: "蓝", value: "0066cc"),
        .init(name: "青", value: "0099cc"), .init(name: "绿", value: "77cc33"),
        .init(name: "橄榄", value: "999900"), .init(name: "黄", value: "ffff00"),
        .init(name: "橙", value: "ff9900"), .init(name: "棕", value: "996633"),
        .init(name: "黑", value: "000000"), .init(name: "灰", value: "999999"),
        .init(name: "浅灰", value: "cccccc"), .init(name: "白", value: "ffffff")
    ]

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                settingsPane
                    .frame(minWidth: 190, idealWidth: 190, maxWidth: 190, maxHeight: .infinity)
                    .layoutPriority(0)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
            }

            mainPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()

            if showInspector {
                Divider()

                detailPane
                    .frame(minWidth: 340, idealWidth: 340, maxWidth: 340, maxHeight: .infinity)
                    .layoutPriority(0)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.18), value: showSidebar)
        .animation(.easeInOut(duration: 0.18), value: showInspector)
        .toolbar {
            ToolbarItem {
                Button {
                    showSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showSidebar ? "隐藏左侧菜单" : "显示左侧菜单")
            }

            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(showInspector ? "隐藏详情" : "显示详情")
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("删除已下载文件？", isPresented: Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )) {
            Button("移到废纸篓", role: .destructive) {
                if let pendingDeleteItem {
                    deleteWallpaper(pendingDeleteItem)
                }
                pendingDeleteID = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteID = nil
            }
        } message: {
            Text("会移除本地图库记录，并把图片文件移到废纸篓。")
        }
    }

    private var settingsPane: some View {
        List(selection: $mainMode) {
            Section("图库") {
                Label(MainPaneMode.online.title, systemImage: MainPaneMode.online.systemImage)
                    .tag(MainPaneMode.online)
                Label(MainPaneMode.gallery.title, systemImage: MainPaneMode.gallery.systemImage)
                    .tag(MainPaneMode.gallery)
            }

            Section("系统") {
                Label(MainPaneMode.configuration.title, systemImage: MainPaneMode.configuration.systemImage)
                    .tag(MainPaneMode.configuration)
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            isVideoWallpaperRunning = VideoWallpaperController.shared.isRunning
            isRotationRunning = WallpaperRotationController.shared.isRunning
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        switch mainMode {
        case .online:
            onlineContent
        case .gallery:
            galleryContent
        case .configuration:
            configurationPane
        }
    }

    private var onlineContent: some View {
        VStack(spacing: 0) {
            onlineControls
            Divider()
            onlineResultToolbar
            Divider()
            onlinePane
        }
    }

    private var galleryContent: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                galleryToolbar
                ScrollView(.horizontal, showsIndicators: false) {
                    galleryToolbar
                        .padding(.bottom, 2)
                }
            }
            .padding(12)

            Divider()
            galleryPane
        }
    }

    private var galleryToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                TextField("按标签筛选", text: $tagFilter)
                    .textFieldStyle(.roundedBorder)

                if !tagFilter.isEmpty {
                    Button {
                        tagFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("清空标签筛选")
                }
            }
            .frame(width: 260)

            Picker("分组", selection: $grouping) {
                ForEach(DownloadGrouping.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            Spacer(minLength: 12)

            Button {
                openWallpaperWall()
            } label: {
                Label("壁纸墙", systemImage: "rectangle.grid.3x2")
            }
            .disabled(filteredItems.isEmpty)
        }
    }

    private var onlineResultToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                paginationControls
                statusLabel
                Spacer()
                searchAndDownloadControls
            }

            VStack(alignment: .leading, spacing: 8) {
                paginationControls
                searchAndDownloadControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var paginationControls: some View {
        HStack(spacing: 10) {
            Button {
                Task { await loadPage(max(1, currentPage - 1)) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(isLoading || currentPage <= 1)

            Text("第 \(currentPage) / \(lastPage) 页 · \(totalCount) 张")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Button {
                Task { await loadPage(min(lastPage, currentPage + 1)) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isLoading || currentPage >= lastPage)
        }
    }

    private var searchAndDownloadControls: some View {
        HStack(spacing: 10) {
            if !onlineImages.isEmpty {
                Button {
                    guard !isLoading else { return }
                    Task { await downloadImages(Array(onlineImages.prefix(downloadCount))) }
                } label: {
                    Label("下载本页", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    private var onlineControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            onlinePrimaryBar
            if showOnlineFilters {
                onlineFilterGrid
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            onlineFilterSummary
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .animation(.easeInOut(duration: 0.16), value: showOnlineFilters)
    }

    private var onlinePrimaryBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Label("在线", systemImage: "globe")
                .font(.subheadline.weight(.semibold))
                .frame(width: 52, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(WallhavenListing.allCases) { item in
                    FilterChip(
                        title: item.title,
                        systemImage: item.systemImage,
                        isSelected: listing == item
                    ) {
                        listing = item
                        sorting = item.defaultSorting
                        currentPage = 1
                        randomSeed = nil
                        if item != .search { query = "" }
                    }
                }
            }

            if listing == .search {
                queryField
                    .frame(minWidth: 260, idealWidth: 360, maxWidth: 520)
            }

            Spacer(minLength: 8)

            Button {
                guard !isLoading else { return }
                Task { await loadPage(1, resetSeed: true) }
            } label: {
                Label(isLoading ? "搜索中" : "搜索", systemImage: "magnifyingglass")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button {
                showOnlineFilters.toggle()
            } label: {
                Label(showOnlineFilters ? "收起" : "筛选", systemImage: showOnlineFilters ? "chevron.up.circle" : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private var onlineFilterSummary: some View {
        HStack(spacing: 6) {
            Text(filterSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
    }

    private var onlineFilterGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            compactFilterRow("排序", systemImage: "arrow.up.arrow.down") {
                Picker("排序", selection: $orderDescending) {
                    Label("倒序", systemImage: "arrow.down").tag(true)
                    Label("正序", systemImage: "arrow.up").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 128)
            }

            if sorting == .toplist {
                compactFilterRow("Top", systemImage: "calendar") {
                    HStack(spacing: 10) {
                        Slider(value: topRangeSliderValue, in: 0...Double(TopRange.allCases.count - 1), step: 1)
                            .frame(width: 220)
                        Text(topRange.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .leading)
                    }
                }
            }

            compactFilterRow("内容", systemImage: "checkmark.shield") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Toggle("General", isOn: $includeGeneral)
                        Toggle("Anime", isOn: $includeAnime)
                        Toggle("People", isOn: $includePeople)
                    }
                    .toggleStyle(.checkbox)

                    WrappingHStack(spacing: 6, rowSpacing: 6) {
                        ForEach(PurityFilter.allCases) { option in
                            if option != .all || allowNSFW {
                                FilterChip(title: option.title, isSelected: purity == option) {
                                    purity = option
                                }
                            }
                        }
                    }
                }
            }

            compactFilterRow("分辨率", systemImage: "display") {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("匹配", selection: $resolutionMode) {
                        ForEach(ResolutionMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 118)

                    WrappingHStack(spacing: 6, rowSpacing: 6) {
                        ForEach(resolutionOptions, id: \.value) { option in
                            FilterChip(title: option.title, isSelected: resolution == option.value) {
                                resolution = option.value
                            }
                        }
                    }
                }
            }

            compactFilterRow("比例", systemImage: "rectangle.inset.filled") {
                WrappingHStack(spacing: 6, rowSpacing: 6) {
                    ForEach(ratioOptions, id: \.value) { option in
                        FilterChip(title: option.title, isSelected: ratios == option.value) {
                            ratios = option.value
                        }
                    }
                }
            }

            compactFilterRow("颜色", systemImage: "paintpalette") {
                WrappingHStack(spacing: 6, rowSpacing: 6) {
                    FilterChip(title: "不限", isSelected: color.isEmpty) {
                        color = ""
                    }
                    ForEach(wallhavenColorOptions) { option in
                        ColorFilterChip(option: option, isSelected: color == option.value) {
                            color = option.value
                        }
                    }
                }
            }

            compactFilterRow("下载", systemImage: "arrow.down.circle") {
                HStack(spacing: 10) {
                    Slider(value: downloadCountSliderValue, in: 1...24, step: 1)
                        .frame(width: 220)
                    Text("\(downloadCount) 张")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                }
            }
        }
    }

    private func compactFilterRow<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(width: 66, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())

            content()
                .padding(.top, 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator.opacity(0.25))
                .frame(height: 0.5)
                .padding(.leading, 92)
        }
    }

    private var queryField: some View {
        HStack(spacing: 4) {
            TextField("关键词 / 标签 / id:123 / @用户", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitOnlineSearch() }

            if !query.isEmpty {
                Button {
                    query = ""
                    submitOnlineSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清空关键词")
            }
        }
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var filterSummary: String {
        var parts: [String] = [
            sorting.title,
            orderDescending ? "倒序" : "正序",
            purity.title
        ]
        if sorting == .toplist {
            parts.append(topRange.title)
        }
        parts.append(resolutionLabel)
        parts.append(ratioLabel)
        if !color.isEmpty {
            parts.append(colorLabel)
        }
        parts.append("\(downloadCount)张")
        return parts.joined(separator: " · ")
    }

    private var resolutionLabel: String {
        resolutionOptions.first { $0.value == resolution }?.title ?? resolution
    }

    private var ratioLabel: String {
        ratioOptions.first { $0.value == ratios }?.title ?? ratios
    }

    private var colorLabel: String {
        wallhavenColorOptions.first { $0.value == color }?.name ?? color
    }

    private var topRangeSliderValue: Binding<Double> {
        Binding(
            get: { Double(TopRange.allCases.firstIndex(of: topRange) ?? 0) },
            set: { value in
                let index = max(0, min(TopRange.allCases.count - 1, Int(value.rounded())))
                topRange = TopRange.allCases[index]
            }
        )
    }

    private var downloadCountSliderValue: Binding<Double> {
        Binding(
            get: { Double(downloadCount) },
            set: { value in
                downloadCount = max(1, min(24, Int(value.rounded())))
            }
        )
    }

    private func submitOnlineSearch() {
        guard mainMode == .online else { return }
        Task { await loadPage(1, resetSeed: true) }
    }

    private var configurationPane: some View {
        Form {
            Section("内容保护") {
                Toggle("允许 NSFW", isOn: $allowNSFW)
                    .onChange(of: allowNSFW) { _, newValue in
                        if !newValue { purity = .sfw }
                    }
                Toggle("Sketchy / NSFW 默认模糊", isOn: $blurNSFW)
                    .disabled(!allowNSFW)
            }

            Section("保存") {
                Picker("保存分组", selection: $grouping) {
                    ForEach(DownloadGrouping.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                HStack {
                    TextField("保存目录", text: $rootPath)
                    Button {
                        chooseRootDirectory()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("选择保存目录")
                }
            }

            Section("Wallhaven") {
                HStack {
                    SecureField("API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveAPIKey() }
                    Button {
                        saveAPIKey()
                    } label: {
                        Label("保存", systemImage: "key")
                    }
                    .help("保存到 Keychain")
                }
            }

            Section("缓存") {
                Button(role: .destructive) {
                    clearAllCaches()
                } label: {
                    Label("清除缓存", systemImage: "trash")
                }
            }

            Section("动态桌面") {
                HStack {
                    Text(videoWallpaperName)
                        .lineLimit(1)
                        .foregroundStyle(videoWallpaperPath.isEmpty ? .secondary : .primary)
                    Spacer()
                    Button {
                        chooseVideoWallpaper()
                    } label: {
                        Image(systemName: "film")
                    }
                    .help("选择本地视频")
                }

                Toggle("全部屏幕", isOn: $videoWallpaperAllScreens)
                Toggle("静音播放", isOn: $videoWallpaperMuted)
                Toggle("低电量模式暂停", isOn: $videoWallpaperPauseInLowPower)

                HStack {
                    Button {
                        startVideoWallpaper()
                    } label: {
                        Label("启动", systemImage: "play.circle")
                    }
                    .disabled(videoWallpaperPath.isEmpty)

                    Button {
                        stopVideoWallpaper()
                    } label: {
                        Label("停止", systemImage: "stop.circle")
                    }
                    .disabled(!isVideoWallpaperRunning)
                }
            }

            Section("自动换壁纸") {
                Picker("顺序", selection: $rotationOrder) {
                    ForEach(WallpaperRotationOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }

                Stepper("间隔：\(rotationIntervalMinutes) 分钟", value: $rotationIntervalMinutes, in: 1...1440)
                Toggle("全部屏幕", isOn: $rotationAllScreens)
                TextField("标签规则，用逗号分隔", text: $rotationRequiredTags)
                Toggle("标签需全部匹配", isOn: $rotationMatchAllTags)
                Toggle("仅 SFW", isOn: $rotationSFWOnly)
                Stepper("最小宽度：\(rotationMinWidth)", value: $rotationMinWidth, in: 0...10000, step: 100)
                Stepper("最小高度：\(rotationMinHeight)", value: $rotationMinHeight, in: 0...10000, step: 100)

                HStack {
                    Button {
                        startWallpaperRotation()
                    } label: {
                        Label("启动", systemImage: "timer")
                    }
                    .disabled(rotationCandidates.isEmpty)

                    Button {
                        rotateWallpaperNow()
                    } label: {
                        Label("下一张", systemImage: "forward")
                    }
                    .disabled(rotationCandidates.isEmpty)

                    Button {
                        stopWallpaperRotation()
                    } label: {
                        Label("停止", systemImage: "stop.circle")
                    }
                    .disabled(!isRotationRunning)
                }
            }

            Section("状态") {
                Text(statusText)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private var onlinePane: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(onlineImages) { image in
                    RemoteWallpaperTile(image: image, blurNSFW: blurNSFW) {
                        Task { await downloadImages([image]) }
                    }
                }
            }
            .padding(16)
            .overlay {
                if onlineImages.isEmpty {
                    ContentUnavailableView("暂无在线结果", systemImage: "globe", description: Text("点搜索加载 Wallhaven 列表"))
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
        }
    }

    private var galleryPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(groupedItems, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.title)
                            .font(.headline)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                            ForEach(group.items) { item in
                                WallpaperTile(item: item, isSelected: selectedID == item.wallhavenID, blurNSFW: blurNSFW)
                                    .onTapGesture { selectedID = item.wallhavenID }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            pendingDeleteID = item.wallhavenID
                                        } label: {
                                            Label("移到废纸篓", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }

                if filteredItems.isEmpty {
                    ContentUnavailableView("暂无壁纸", systemImage: "photo.on.rectangle", description: Text("下载后会显示在这里"))
                        .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let selectedItem {
            WallpaperDetailView(
                item: selectedItem,
                blurNSFW: blurNSFW,
                preview: {
                    QuickLookPreviewer.shared.show(url: selectedItem.fileURL)
                },
                revealInFinder: {
                    NSWorkspace.shared.activateFileViewerSelecting([selectedItem.fileURL])
                },
                setWallpaper: { allScreens in
                    do {
                        try service.setDesktopWallpaper(selectedItem.fileURL, onAllScreens: allScreens)
                        statusText = allScreens ? "已设置为全部屏幕壁纸" : "已设置为当前屏幕壁纸"
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                },
                delete: {
                    pendingDeleteID = selectedItem.wallhavenID
                }
            )
        } else {
            ContentUnavailableView("选择一张本地壁纸", systemImage: "sidebar.right", description: Text("可编辑标签或设置为桌面壁纸"))
        }
    }

    private var selectedItem: WallpaperItem? {
        items.first { $0.wallhavenID == selectedID } ?? filteredItems.first
    }

    private var pendingDeleteItem: WallpaperItem? {
        guard let pendingDeleteID else { return nil }
        return items.first { $0.wallhavenID == pendingDeleteID }
    }

    private var videoWallpaperName: String {
        guard !videoWallpaperPath.isEmpty else { return "未选择视频" }
        return URL(fileURLWithPath: videoWallpaperPath).lastPathComponent
    }

    private var rotationCandidates: [WallpaperRotationCandidate] {
        items.compactMap(WallpaperRotationCandidate.init)
    }

    private var rotationRule: WallpaperRotationRule {
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

    private var filteredItems: [WallpaperItem] {
        let query = tagFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.tags.contains { $0.lowercased().contains(query) }
        }
    }

    private var groupedItems: [(title: String, items: [WallpaperItem])] {
        let groups = Dictionary(grouping: filteredItems) { item in
            grouping == .month ? item.groupMonth : item.groupDay
        }
        return groups
            .map { (title: $0.key, items: $0.value.sorted { $0.downloadedAt > $1.downloadedAt }) }
            .sorted { $0.title > $1.title }
    }

    private var categoryValue: String {
        "\(includeGeneral ? 1 : 0)\(includeAnime ? 1 : 0)\(includePeople ? 1 : 0)"
    }

    private func searchOptions(page: Int) -> WallhavenSearchOptions {
        let effectiveSorting = listing == .search ? sorting : listing.defaultSorting
        return WallhavenSearchOptions(
            listing: listing,
            query: listing == .search ? query : "",
            categories: categoryValue == "000" ? "100" : categoryValue,
            purity: allowNSFW ? purity : .sfw,
            sorting: effectiveSorting,
            orderDescending: orderDescending,
            topRange: topRange,
            resolutionMode: resolutionMode,
            resolution: resolution,
            ratios: ratios,
            color: color,
            apiKey: apiKey,
            page: page,
            seed: effectiveSorting == .random ? randomSeed : nil
        )
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

    private func chooseVideoWallpaper() {
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
            statusText = "已选择动态桌面视频"
        }
    }

    private func startVideoWallpaper() {
        do {
            try VideoWallpaperController.shared.start(VideoWallpaperConfiguration(
                videoURL: URL(fileURLWithPath: videoWallpaperPath),
                allScreens: videoWallpaperAllScreens,
                muted: videoWallpaperMuted,
                pauseInLowPowerMode: videoWallpaperPauseInLowPower
            ))
            isVideoWallpaperRunning = true
            statusText = videoWallpaperAllScreens ? "动态桌面已启动：全部屏幕" : "动态桌面已启动：当前屏幕"
        } catch {
            isVideoWallpaperRunning = false
            errorMessage = error.localizedDescription
        }
    }

    private func stopVideoWallpaper() {
        VideoWallpaperController.shared.stop()
        isVideoWallpaperRunning = false
        statusText = "动态桌面已停止"
    }

    private func startWallpaperRotation() {
        do {
            try WallpaperRotationController.shared.start(
                candidates: rotationCandidates,
                rule: rotationRule
            )
            isRotationRunning = true
            statusText = "自动换壁纸已启动"
        } catch {
            isRotationRunning = false
            errorMessage = error.localizedDescription
        }
    }

    private func rotateWallpaperNow() {
        do {
            if WallpaperRotationController.shared.isRunning {
                try WallpaperRotationController.shared.rotateNow()
            } else {
                try WallpaperRotationController.shared.start(
                    candidates: rotationCandidates,
                    rule: rotationRule
                )
                isRotationRunning = true
            }
            statusText = "已切换到下一张壁纸"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func stopWallpaperRotation() {
        WallpaperRotationController.shared.stop()
        isRotationRunning = false
        statusText = "自动换壁纸已停止"
    }

    private func saveAPIKey() {
        do {
            try KeychainStore.saveAPIKey(apiKey)
            statusText = "API Key 已保存到 Keychain"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteWallpaper(_ item: WallpaperItem) {
        do {
            if FileManager.default.fileExists(atPath: item.fileURL.path) {
                _ = try FileManager.default.trashItem(at: item.fileURL, resultingItemURL: nil)
            }
            if selectedID == item.wallhavenID {
                selectedID = nil
            }
            modelContext.delete(item)
            try modelContext.save()
            statusText = "已移到废纸篓"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearAllCaches() {
        Task {
            do {
                try await AppCacheStore.shared.clearAll()
                await MainActor.run {
                    statusText = "已清除缓存"
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func openWallpaperWall() {
        WallpaperWallWindowController.shared.show(rootView: WallpaperWallView(
            items: filteredItems.map(WallpaperWallItem.init),
            blurNSFW: blurNSFW,
            close: {
                WallpaperWallWindowController.shared.close()
            },
            setWallpaper: { wallItem in
                do {
                    try service.setDesktopWallpaper(wallItem.fileURL)
                    selectedID = wallItem.id
                    statusText = "已设置为当前屏幕壁纸"
                    return true
                } catch {
                    errorMessage = error.localizedDescription
                    return false
                }
            },
            toggleFavoriteAction: { id in
                guard let item = items.first(where: { $0.wallhavenID == id }) else { return }
                var tags = item.tags
                if tags.contains("favorite") {
                    tags.removeAll { $0 == "favorite" }
                } else {
                    tags.append("favorite")
                }
                item.tagsText = tags.joined(separator: ", ")
                try? modelContext.save()
            },
            select: { id in
                selectedID = id
            }
        ))
    }

    @MainActor
    private func loadPage(_ page: Int, resetSeed: Bool = false) async {
        isLoading = true
        statusText = "正在加载 Wallhaven 第 \(page) 页"
        if resetSeed { randomSeed = nil }
        defer { isLoading = false }

        do {
            let result = try await service.search(searchOptions(page: page))
            onlineImages = result.images
            currentPage = result.meta.currentPage
            lastPage = max(1, result.meta.lastPage)
            totalCount = result.meta.total
            if sorting == .random || listing == .random {
                randomSeed = result.meta.seed
            }
            mainMode = .online
            statusText = result.isFromCache ? "已从缓存加载 \(result.images.count) 张在线结果" : "已加载 \(result.images.count) 张在线结果"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "加载失败"
        }
    }

    @MainActor
    private func downloadImages(_ images: [WallhavenImage]) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let existingIDs = Set(items.map(\.wallhavenID))
            var savedCount = 0

            for image in images where !existingIDs.contains(image.id) {
                statusText = "正在下载 wallhaven-\(image.id)"
                let result = try await service.download(
                    image,
                    grouping: grouping,
                    rootDirectory: URL(fileURLWithPath: rootPath)
                )
                modelContext.insert(WallpaperItem(
                    wallhavenID: image.id,
                    sourceURL: image.url,
                    imageURL: image.path,
                    localPath: result.localURL.path,
                    purity: image.purity,
                    resolution: image.resolution,
                    fileSize: image.fileSize
                ))
                savedCount += 1
            }

            try modelContext.save()
            statusText = savedCount == 0 ? "没有新的候选壁纸" : "已下载 \(savedCount) 张"
        } catch {
            errorMessage = error.localizedDescription
            statusText = "下载失败"
        }
    }
}

private extension WallhavenListing {
    var systemImage: String {
        switch self {
        case .latest: "clock"
        case .hot: "flame"
        case .toplist: "chart.bar"
        case .random: "shuffle"
        case .search: "person.crop.circle.badge.magnifyingglass"
        }
    }
}

private struct FilterOption {
    let title: String
    let value: String
}

private struct WallhavenColorOption: Identifiable {
    let name: String
    let value: String

    var id: String { value }

    var color: Color {
        Color(hex: value)
    }
}

private struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ColorFilterChip: View {
    let option: WallhavenColorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(option.color)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Circle()
                            .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
                Text(option.name)
                    .lineLimit(1)
            }
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.map(\.height).reduce(0, +) + CGFloat(max(0, rows.count - 1)) * rowSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [FlowRow] = []
        var current = FlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width

            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = FlowRow()
            }

            current.indices.append(index)
            current.width = current.width == 0 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct FlowRow {
        var indices: [Subviews.Index] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }
}

private extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xff) / 255.0,
            green: Double((value >> 8) & 0xff) / 255.0,
            blue: Double(value & 0xff) / 255.0
        )
    }
}

struct RemoteWallpaperTile: View {
    let image: WallhavenImage
    let blurNSFW: Bool
    let download: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SensitiveImage(blurRadius: wallpaperBlurRadius(for: image.purity, enabled: blurNSFW)) {
                CachedRemoteImageView(url: image.thumbs.large)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                MetadataBadge(title: image.category.capitalized, systemImage: "square.grid.2x2")
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                PurityBadge(purity: image.purity)
                    .padding(8)
            }
            .overlay(alignment: .bottomLeading) {
                MetadataBadge(title: image.resolution, systemImage: "rectangle")
                    .padding(8)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("wallhaven-\(image.id)")
                        .font(.caption)
                    Text(image.url.host() ?? "wallhaven.cc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: download) {
                    Image(systemName: "arrow.down")
                }
                .help("下载这张")
            }
        }
        .padding(8)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

}

struct WallpaperTile: View {
    let item: WallpaperItem
    let isSelected: Bool
    let blurNSFW: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SensitiveImage(blurRadius: wallpaperBlurRadius(for: item.purity, enabled: blurNSFW)) {
                LocalImageView(url: item.fileURL)
            }
                .aspectRatio(16 / 10, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    PurityBadge(purity: item.purity)
                        .padding(8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 3 : 1)
                }

            HStack {
                Text(item.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !item.tags.isEmpty {
                    MetadataBadge(title: "\(item.tags.count)", systemImage: "tag")
                }
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(item.fileURL)
    }

}

struct WallpaperDetailView: View {
    @Bindable var item: WallpaperItem
    let blurNSFW: Bool
    let preview: () -> Void
    let revealInFinder: () -> Void
    let setWallpaper: (Bool) -> Void
    let delete: () -> Void

    var body: some View {
        Form {
            Section {
                SensitiveImage(blurRadius: wallpaperBlurRadius(for: item.purity, enabled: blurNSFW)) {
                    LocalImageView(url: item.fileURL)
                }
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topTrailing) {
                        PurityBadge(purity: item.purity)
                            .padding(8)
                    }

                HStack {
                    Button(action: preview) {
                        Label("预览", systemImage: "eye")
                    }

                    Button(action: revealInFinder) {
                        Label("Finder", systemImage: "folder")
                    }
                }

                Button {
                    setWallpaper(false)
                } label: {
                    Label("设为当前屏幕", systemImage: "desktopcomputer")
                }

                Button {
                    setWallpaper(true)
                } label: {
                    Label("设为全部屏幕", systemImage: "rectangle.on.rectangle")
                }

                Button(role: .destructive, action: delete) {
                    Label("删除已下载文件", systemImage: "trash")
                }
            }

            Section("信息") {
                LabeledContent("Wallhaven ID", value: item.wallhavenID)
                LabeledContent("分辨率", value: item.resolution)
                LabeledContent("类型", value: item.purity.uppercased())
                Link("打开来源", destination: item.sourceURL)
            }

            Section("标签") {
                TextField("标签，用逗号分隔", text: $item.tagsText)
            }
        }
        .formStyle(.grouped)
    }

}

struct PurityBadge: View {
    let purity: String

    var body: some View {
        Text(purity.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundStyle)
            .background(backgroundStyle, in: Capsule())
            .accessibilityLabel("类型 \(purity.uppercased())")
    }

    private var backgroundStyle: Color {
        switch purity.lowercased() {
        case "sfw":
            Color.green.opacity(0.18)
        case "sketchy":
            Color.yellow.opacity(0.24)
        case "nsfw":
            Color.red.opacity(0.22)
        default:
            Color.secondary.opacity(0.18)
        }
    }

    private var foregroundStyle: Color {
        switch purity.lowercased() {
        case "sfw":
            .green
        case "sketchy":
            .orange
        case "nsfw":
            .red
        default:
            .secondary
        }
    }
}

struct MetadataBadge: View {
    let title: String
    let systemImage: String?

    init(title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
    }
}

struct SensitiveImage<Content: View>: View {
    let blurRadius: CGFloat
    let content: () -> Content
    @State private var isRevealed = false

    init(isSensitive: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.blurRadius = isSensitive ? 18 : 0
        self.content = content
    }

    init(blurRadius: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.blurRadius = blurRadius
        self.content = content
    }

    var body: some View {
        ZStack {
            content()
                .blur(radius: isHidden ? blurRadius : 0)

            if isHidden {
                Rectangle()
                    .fill(.regularMaterial)
                    .opacity(0.86)

                Button {
                    isRevealed = true
                } label: {
                    Image(systemName: "eye.fill")
                        .font(.title3)
                        .padding(10)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("显示 NSFW 预览")
                .accessibilityLabel("显示 NSFW 预览")
            } else if isSensitive {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isRevealed = false
                        } label: {
                            Image(systemName: "eye.slash.fill")
                                .font(.caption)
                                .padding(7)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("隐藏 NSFW 预览")
                        .accessibilityLabel("隐藏 NSFW 预览")
                    }
                    Spacer()
                }
                .padding(8)
            }
        }
        .clipped()
    }

    private var isHidden: Bool {
        isSensitive && !isRevealed
    }

    private var isSensitive: Bool {
        blurRadius > 0
    }
}

func wallpaperBlurRadius(for purity: String, enabled: Bool) -> CGFloat {
    guard enabled else { return 0 }
    switch purity.lowercased() {
    case "sketchy":
        return 8
    case "nsfw":
        return 24
    default:
        return 0
    }
}

struct LocalImageView: View {
    let url: URL
    var maxPixelSize: CGFloat = 1200
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .task(id: "\(url.path)-\(Int(maxPixelSize))") {
            image = await LocalImageLoader.load(url: url, maxPixelSize: maxPixelSize)
        }
    }
}
