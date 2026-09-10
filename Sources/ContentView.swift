import AppKit
import SwiftData
import SwiftUI

/// 全局布局度量，避免各处重复的魔法数字。
private enum LayoutMetrics {
    static let cardCornerRadius: CGFloat = 10
    static let thumbnailRatio: CGFloat = 3 / 2
    static let heroCornerRadius: CGFloat = 12
    static let heroPadding: CGFloat = 20
    static let heroOverlayPadding: CGFloat = 28
    /// 主图按舞台尺寸解码的上限，超过这个像素数对肉眼已无收益。
    static let heroMaxPixelCap: CGFloat = 2600
    static let ambientBlurRadius: CGFloat = 32
    static let ambientPixelSize: CGFloat = 120
    static let filmstripCellWidth: CGFloat = 84
    static let filmstripCellHeight: CGFloat = 56
    static let filmstripSpacing: CGFloat = 8
    /// 横向 ScrollView 在竖向上是贪婪的，不钉死高度会和舞台对分空间。
    static let filmstripHeight: CGFloat = 80
    static let filmstripRemotePixelSize: CGFloat = 160
    static let filmstripLocalPixelSize: CGFloat = 200
    static let inspectorPreviewPixelSize: CGFloat = 900
    /// 距缓冲区末尾还剩这么多张时开始静默续页。
    static let loadMoreThreshold = 3

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    static var heroShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: heroCornerRadius, style: .continuous)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
    @AppStorage("downloadCount") private var downloadCount = 24
    @AppStorage("rootPath") private var rootPath = WallhavenService.defaultRootDirectory.path
    @State private var tagFilter = ""
    @State private var selectedID: String?
    /// 累积缓冲区：按页追加而非替换，方向键逐张消费。
    @State private var onlineBuffer: [WallhavenImage] = []
    @State private var onlineIndex = 0
    @State private var localIndex = 0
    @State private var currentPage = 1
    @State private var lastPage = 1
    @State private var totalCount = 0
    @State private var randomSeed: String?
    /// 按方向键时数据仍在加载，加载完成后补一次前进。
    @State private var pendingAdvance = false
    @State private var isStageHovered = false
    /// 桌面壁纸模拟预览：只看不改，不写系统桌面。
    @State private var isWallpaperPreviewing = false
    /// 由舞台实际尺寸推导出的主图解码像素上限。
    @State private var stagePixelSize: CGFloat = 1600
    @AppStorage("mainPaneMode") private var mainMode: MainPaneMode = .online
    @AppStorage("showFilmstrip") private var showFilmstrip = true
    @AppStorage("showOnlineFilters") private var showOnlineFilters = false
    @State private var showInspector = false
    @State private var isLoading = false
    @State private var statusText = "就绪"
    @State private var errorMessage: String?
    @State private var onlineErrorMessage: String?
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
        VStack(spacing: 0) {
            filterBar

            Divider()

            heroStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            if showFilmstrip, hasBrowseItems {
                Divider()

                filmstrip
            }

            Divider()

            statusBar
        }
        .background(KeyCatcher(handler: handleKey))
        .overlay {
            wallpaperPreviewLayer
                .animation(.easeOut(duration: 0.18), value: isWallpaperPreviewing)
        }
        .navigationTitle(mainMode.title)
        .inspector(isPresented: $showInspector) {
            detailPane
                .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    Button {
                        isWallpaperPreviewing.toggle()
                    } label: {
                        Image(systemName: "rectangle.on.rectangle")
                            .symbolVariant(isWallpaperPreviewing ? .fill : .none)
                    }
                    .help(isWallpaperPreviewing ? "退出桌面预览" : "桌面壁纸预览")
                    .disabled(currentBrowseID == nil)

                    Button {
                        showFilmstrip.toggle()
                    } label: {
                        Image(systemName: "film")
                            .symbolVariant(showFilmstrip ? .fill : .none)
                    }
                    .help(showFilmstrip ? "隐藏缩略图条" : "显示缩略图条")

                    Button {
                        showInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(showInspector ? "隐藏详情" : "显示详情")
                }
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
        .onChange(of: tagFilter) { _, _ in
            localIndex = 0
        }
        .onChange(of: filteredItems.count) { _, count in
            localIndex = min(localIndex, max(0, count - 1))
        }
        .onChange(of: currentLocalItem?.wallhavenID) { _, id in
            selectedID = id
        }
        .onChange(of: mainMode) { _, mode in
            // 回到图库时检查器必须跟舞台对齐，而不是停在壁纸墙或设为壁纸留下的选择上。
            if mode == .gallery {
                selectedID = currentLocalItem?.wallhavenID
            }
        }
        .task(id: prefetchKey) {
            await prefetchNext()
        }
    }

    /// 两种模式共用的底部状态条：操作结果、当前位置、快捷键提示与整体进度。
    private var statusBar: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(2)

            Text(positionText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(keyboardHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .contentTransition(.opacity)
    }

    /// 分页控件移除后，进度信息全部收敛到这一行。
    private var positionText: String {
        switch mainMode {
        case .online:
            guard !onlineBuffer.isEmpty else { return "" }
            return "第 \(onlineIndex + 1) / \(onlineBuffer.count) 张 · 已取 \(currentPage)/\(lastPage) 页 · 共 \(totalCount) 张"
        case .gallery:
            guard !filteredItems.isEmpty else { return "" }
            return "第 \(localIndex + 1) / \(filteredItems.count) 张"
        }
    }

    private var keyboardHint: String {
        switch mainMode {
        case .online:
            "← → 切换 · 空格 下载 · 回车 打开来源"
        case .gallery:
            "← → 切换 · 空格 设为壁纸 · 回车 预览"
        }
    }

    // MARK: - 桌面壁纸模拟预览

    @ViewBuilder
    private var wallpaperPreviewLayer: some View {
        if isWallpaperPreviewing {
            wallpaperPreview
                .transition(.opacity)
        }
    }

    /// 全屏模拟桌面壁纸效果：图片铺满 + 仿菜单栏，退出前不写系统桌面。
    private var wallpaperPreview: some View {
        ZStack {
            Color.black

            previewWallpaperImage
                .clipped()

            VStack(spacing: 0) {
                previewMenuBar
                Spacer()
                previewExitPill
                    .padding(.bottom, 30)
            }
        }
        .foregroundStyle(.white)
        .ignoresSafeArea()
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var previewWallpaperImage: some View {
        let pixelSize = heroPixelSize(for: NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080))
        switch mainMode {
        case .online:
            if let image = currentOnlineImage {
                CachedRemoteImageView(
                    url: image.path,
                    maxPixelSize: pixelSize,
                    contentMode: .fill,
                    referer: image.url,
                    loadingHint: "正在加载原图"
                )
            }
        case .gallery:
            if let item = currentLocalItem {
                LocalImageView(url: item.fileURL, maxPixelSize: pixelSize, showsPlaceholderBackground: false)
                    .scaledToFill()
            }
        }
    }

    private var previewMenuBar: some View {
        HStack(spacing: 12) {
            Text("桌面壁纸预览")
                .font(.callout.weight(.semibold))

            Text(previewCaption)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text("Esc 退出")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.ultraThinMaterial)
    }

    private var previewCaption: String {
        switch mainMode {
        case .online:
            guard let image = currentOnlineImage else { return "" }
            return "wallhaven-\(image.id) · \(image.resolution)"
        case .gallery:
            guard let item = currentLocalItem else { return "" }
            return "wallhaven-\(item.wallhavenID) · \(item.resolution)"
        }
    }

    private var previewExitPill: some View {
        HStack(spacing: 12) {
            Label("仅模拟效果，不会修改系统桌面", systemImage: "info.circle")
                .font(.callout)

            Button("退出预览") {
                isWallpaperPreviewing = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    // MARK: - 顶部筛选表单

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                filterPrimaryBar
                filterPrimaryBarWrapped
            }

            if mainMode == .online {
                if showOnlineFilters {
                    onlineFilterDrawer
                        .padding(.top, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let onlineErrorMessage, !onlineBuffer.isEmpty {
                    onlineWarningBanner(onlineErrorMessage)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .animation(.easeInOut(duration: 0.16), value: showOnlineFilters)
    }

    private var filterPrimaryBar: some View {
        HStack(alignment: .center, spacing: 10) {
            modePicker
            Divider().frame(height: 18)
            modeSpecificControls
            Spacer(minLength: 8)

            if mainMode == .online {
                filterSummaryLabel
            }

            Divider().frame(height: 18)
            filterActions
            Divider().frame(height: 18)

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("设置")
        }
    }

    /// 窄窗口折行：模式与动作留在首行，来源 / 筛选条件换到第二行。
    private var filterPrimaryBarWrapped: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                modePicker
                Spacer(minLength: 8)
                filterActions
                Divider().frame(height: 18)

                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .help("设置")
            }

            modeSpecificControls
        }
    }

    @ViewBuilder
    private var modeSpecificControls: some View {
        switch mainMode {
        case .online:
            listingSelector

            if listing == .search {
                queryField
                    .frame(minWidth: 200, idealWidth: 320, maxWidth: 460)
            }
        case .gallery:
            tagFilterField
                .frame(width: 240)
        }
    }

    /// 侧栏移除后，在线与本地图库靠这个分段控件切换。
    private var modePicker: some View {
        Picker("模式", selection: $mainMode) {
            ForEach(MainPaneMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 176)
    }

    private var tagFilterField: some View {
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
    }

    @ViewBuilder
    private var filterActions: some View {
        switch mainMode {
        case .online:
            onlineActions
        case .gallery:
            galleryActions
        }
    }

    private var onlineActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    if let currentOnlineImage {
                        Task { await downloadImages([currentOnlineImage]) }
                    }
                } label: {
                    Label("下载当前张", systemImage: "arrow.down")
                }
                .disabled(currentOnlineImage == nil || isDownloaded(currentOnlineImage))

                Button {
                    Task { await downloadImages(browsedOnlineImages) }
                } label: {
                    Label("下载已浏览的 \(browsedOnlineImages.count) 张", systemImage: "square.and.arrow.down")
                }
                .disabled(browsedOnlineImages.isEmpty)
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .disabled(isLoading)

            Button {
                showOnlineFilters.toggle()
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease")
                    .symbolVariant(showOnlineFilters ? .fill : .none)
            }
            .buttonStyle(.bordered)
            .help(showOnlineFilters ? "收起筛选" : "展开筛选")

            Button {
                guard !isLoading else { return }
                Task { await loadPage(1, resetSeed: true) }
            } label: {
                Label(isLoading ? "加载中" : primaryActionTitle, systemImage: listing == .search ? "magnifyingglass" : "arrow.clockwise")
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
    }

    private var galleryActions: some View {
        HStack(spacing: 8) {
            Button {
                if let currentLocalItem {
                    setDesktopWallpaper(currentLocalItem)
                }
            } label: {
                Label("设为壁纸", systemImage: "desktopcomputer")
            }
            .buttonStyle(.borderedProminent)
            .disabled(currentLocalItem == nil)

            Button {
                openWallpaperWall()
            } label: {
                Label("壁纸墙", systemImage: "rectangle.grid.3x2")
            }
            .disabled(filteredItems.isEmpty)
        }
    }

    /// 「下载已浏览的 N 张」：从缓冲区开头到当前张，取最后 downloadCount 张。
    private var browsedOnlineImages: [WallhavenImage] {
        guard !onlineBuffer.isEmpty else { return [] }
        let upperBound = min(max(0, onlineIndex), onlineBuffer.count - 1)
        let browsed = Array(onlineBuffer[0...upperBound])
        return Array(browsed.suffix(min(downloadCount, browsed.count)))
    }

    private var downloadedIDs: Set<String> {
        Set(items.map(\.wallhavenID))
    }

    private func isDownloaded(_ image: WallhavenImage?) -> Bool {
        guard let image else { return false }
        return downloadedIDs.contains(image.id)
    }

    private var filterSummaryLabel: some View {
        Label(filterSummary, systemImage: "slider.horizontal.3")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(filterSummary)
    }

    /// 来源用原生分段控件：比一排自定义芯片更紧凑，也和模式切换同一视觉语言。
    private var listingSelector: some View {
        Picker("来源", selection: $listing) {
            ForEach(WallhavenListing.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 336)
        .help("浏览来源")
        .onChange(of: listing) { _, item in
            sorting = item.defaultSorting
            currentPage = 1
            randomSeed = nil
            onlineErrorMessage = nil
            if item != .search { query = "" }
        }
    }

    private var primaryActionTitle: String {
        switch listing {
        case .latest: "加载最新"
        case .hot: "加载热门"
        case .toplist: "加载榜单"
        case .random: "换一批"
        case .search: "搜索"
        }
    }

    /// 筛选抽屉：整块一个面板，左右两列、标签列定宽对齐，避免卡片高低错落留下空洞。
    private var onlineFilterDrawer: some View {
        ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    filterRow("排序", systemImage: "arrow.up.arrow.down") {
                        HStack(spacing: 12) {
                            Picker("排序", selection: $orderDescending) {
                                Label("倒序", systemImage: "arrow.down").tag(true)
                                Label("正序", systemImage: "arrow.up").tag(false)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 128)

                            if sorting == .toplist {
                                Slider(value: topRangeSliderValue, in: 0...Double(TopRange.allCases.count - 1), step: 1)
                                Text(topRange.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 44, alignment: .leading)
                            }
                        }
                    }

                    filterRow("分辨率", systemImage: "display") {
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

                    filterRow("颜色", systemImage: "paintpalette") {
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
                }

                VStack(alignment: .leading, spacing: 14) {
                    filterRow("内容", systemImage: "checkmark.shield") {
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

                    filterRow("比例", systemImage: "rectangle.inset.filled") {
                        WrappingHStack(spacing: 6, rowSpacing: 6) {
                            ForEach(ratioOptions, id: \.value) { option in
                                FilterChip(title: option.title, isSelected: ratios == option.value) {
                                    ratios = option.value
                                }
                            }
                        }
                    }

                    filterRow("下载", systemImage: "arrow.down.circle") {
                        HStack(spacing: 12) {
                            Slider(value: downloadCountSliderValue, in: 1...24, step: 1)
                            Text("\(downloadCount) 张")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .leading)
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 232)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.5),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 0.5)
        }
    }

    /// 抽屉行：标签列定宽并顶到控件首行，两列内容的左边缘因此严格对齐。
    private func filterRow<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 5)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - 单张大图舞台

    private var heroStage: some View {
        GeometryReader { proxy in
            ZStack {
                stageBackground

                stageContent(pixelSize: heroPixelSize(for: proxy.size))

                stageOverlays
            }
            .contentShape(Rectangle())
            .preferredColorScheme(.dark)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: currentBrowseID)
            .onHover { isStageHovered = $0 }
            .onAppear { stagePixelSize = heroPixelSize(for: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                stagePixelSize = heroPixelSize(for: newSize)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// 主图按舞台实际尺寸解码，窗口拉大后不会发虚；封顶避免无收益的超大解码。
    private func heroPixelSize(for size: CGSize) -> CGFloat {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return min(max(size.width, size.height) * scale, LayoutMetrics.heroMaxPixelCap)
    }

    /// 环境光背景：当前图的极低分辨率缩略图放大模糊，让舞台颜色跟着图片走。
    @ViewBuilder
    private var stageBackground: some View {
        Color(nsColor: .underPageBackgroundColor)

        if !reduceTransparency {
            ambientImage
                .blur(radius: LayoutMetrics.ambientBlurRadius, opaque: true)
                .opacity(0.5)
                .overlay {
                    Color.black.opacity(0.5)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var ambientImage: some View {
        switch mainMode {
        case .online:
            if let image = currentOnlineImage {
                CachedRemoteImageView(url: image.thumbs.large, maxPixelSize: LayoutMetrics.ambientPixelSize)
            }
        case .gallery:
            if let item = currentLocalItem {
                LocalImageView(url: item.fileURL, maxPixelSize: LayoutMetrics.ambientPixelSize, showsPlaceholderBackground: false)
                    .scaledToFill()
            }
        }
    }

    @ViewBuilder
    private func stageContent(pixelSize: CGFloat) -> some View {
        switch mainMode {
        case .online:
            onlineHero(pixelSize: pixelSize)
        case .gallery:
            localHero(pixelSize: pixelSize)
        }
    }

    /// 在线主图取原图而非 700px 缩略图，并带 Referer 避免 CDN 拒绝外链。
    @ViewBuilder
    private func onlineHero(pixelSize: CGFloat) -> some View {
        if let image = currentOnlineImage {
            SensitiveImage(blurRadius: wallpaperBlurRadius(for: image.purity, enabled: blurNSFW)) {
                CachedRemoteImageView(
                    url: image.path,
                    maxPixelSize: pixelSize,
                    contentMode: .fit,
                    referer: image.url,
                    loadingHint: "正在加载原图"
                )
            }
            .clipShape(LayoutMetrics.heroShape)
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .padding(LayoutMetrics.heroPadding)
            .id(image.id)
            .transition(.opacity)
            .onTapGesture(count: 2) {
                NSWorkspace.shared.open(image.url)
            }
            .accessibilityLabel("wallhaven-\(image.id)，\(image.resolution)")
        } else {
            onlineEmptyState
        }
    }

    @ViewBuilder
    private func localHero(pixelSize: CGFloat) -> some View {
        if let item = currentLocalItem {
            SensitiveImage(blurRadius: wallpaperBlurRadius(for: item.purity, enabled: blurNSFW)) {
                LocalImageView(url: item.fileURL, maxPixelSize: pixelSize, showsPlaceholderBackground: false)
                    .scaledToFit()
            }
            .clipShape(LayoutMetrics.heroShape)
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .padding(LayoutMetrics.heroPadding)
            .id(item.wallhavenID)
            .transition(.opacity)
            .onTapGesture(count: 2) {
                QuickLookPreviewer.shared.show(url: item.fileURL)
            }
            .draggable(item.fileURL)
            .accessibilityLabel("wallhaven-\(item.wallhavenID)，\(item.resolution)")
        } else {
            galleryEmptyState
        }
    }

    @ViewBuilder
    private var onlineEmptyState: some View {
        if isLoading {
            stageProgress("正在加载 Wallhaven")
        } else if let onlineErrorMessage {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(onlineErrorMessage)
            } actions: {
                onlineEmptyActions(primaryTitle: "重试")
            }
            .foregroundStyle(.white.opacity(0.85))
        } else {
            ContentUnavailableView {
                Label("暂无在线结果", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("从 \(listing.title) 加载壁纸，或调整筛选条件后重试")
            } actions: {
                onlineEmptyActions(primaryTitle: primaryActionTitle)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func stageProgress(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)

            Text(text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    /// 箭头与悬浮信息只在有内容时出现，避免空态下压住按钮。
    @ViewBuilder
    private var stageOverlays: some View {
        if hasBrowseItems {
            HStack {
                stageArrow(systemName: "chevron.left", help: "上一张（←）", disabled: !canGoPrevious) {
                    advance(-1)
                }

                Spacer()

                stageArrow(systemName: "chevron.right", help: "下一张（→）", disabled: !canGoNext) {
                    advance(1)
                }
            }
            .padding(.horizontal, 10)
            .opacity(isStageHovered ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: isStageHovered)
            .allowsHitTesting(isStageHovered)

            VStack {
                heroTopBadges
                Spacer()
                heroBottomRow
            }
            .padding(LayoutMetrics.heroOverlayPadding)
        }
    }

    private func stageArrow(systemName: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 96)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.white.opacity(disabled ? 0.25 : 0.85))
        .disabled(disabled)
        .help(help)
    }

    private var heroTopBadges: some View {
        HStack(alignment: .top) {
            MetadataBadge(title: "wallhaven-\(currentBrowseID ?? "")")

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let currentPurity, currentPurity.lowercased() != "sfw" {
                    PurityBadge(purity: currentPurity)
                }

                if mainMode == .online, isDownloaded(currentOnlineImage) {
                    MetadataBadge(title: "已下载", systemImage: "checkmark.circle.fill")
                }
            }
        }
    }

    private var heroBottomRow: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 6) {
                MetadataBadge(title: currentResolution)

                if let currentCategory {
                    MetadataBadge(title: currentCategory)
                }

                if let currentFileSize {
                    MetadataBadge(title: ByteCountFormatter.string(fromByteCount: Int64(currentFileSize), countStyle: .file))
                }
            }

            Spacer(minLength: 12)

            heroActions
        }
    }

    @ViewBuilder
    private var heroActions: some View {
        switch mainMode {
        case .online:
            if let image = currentOnlineImage {
                HStack(spacing: 8) {
                    Link(destination: image.url) {
                        Label("来源", systemImage: "safari")
                    }

                    Button {
                        Task { await downloadImages([image]) }
                    } label: {
                        Label(isDownloaded(image) ? "已下载" : "下载",
                              systemImage: isDownloaded(image) ? "checkmark.circle.fill" : "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDownloaded(image) || isLoading)
                }
                .buttonStyle(.bordered)
            }
        case .gallery:
            if let item = currentLocalItem {
                HStack(spacing: 8) {
                    Button {
                        toggleFavorite(item)
                    } label: {
                        Image(systemName: item.tags.contains("favorite") ? "heart.fill" : "heart")
                    }
                    .help(item.tags.contains("favorite") ? "取消收藏" : "收藏")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help("在 Finder 中显示")

                    Button {
                        QuickLookPreviewer.shared.show(url: item.fileURL)
                    } label: {
                        Image(systemName: "eye")
                    }
                    .help("快速预览")

                    Button {
                        setDesktopWallpaper(item)
                    } label: {
                        Label("设为壁纸", systemImage: "desktopcomputer")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - 底部缩略图条

    private var filmstrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: LayoutMetrics.filmstripSpacing) {
                    if mainMode == .online {
                        onlineFilmstripCells
                    } else {
                        localFilmstripCells
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(height: LayoutMetrics.filmstripHeight)
            .background(.bar)
            .onChange(of: currentBrowseID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    reader.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    /// 已下载集合只算一次，避免在 ForEach 里重复构造。
    private var onlineFilmstripCells: some View {
        let downloadedIDs = self.downloadedIDs
        return ForEach(onlineBuffer) { image in
            FilmstripCell(isSelected: image.id == currentOnlineImage?.id) {
                CachedRemoteImageView(url: image.thumbs.large, maxPixelSize: LayoutMetrics.filmstripRemotePixelSize)
            }
            .overlay(alignment: .bottomTrailing) {
                if downloadedIDs.contains(image.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                        .padding(4)
                }
            }
            .id(image.id)
            .onTapGesture {
                jumpToOnline(image.id)
            }
            .contextMenu {
                Button {
                    Task { await downloadImages([image]) }
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                }
                .disabled(downloadedIDs.contains(image.id))

                Link(destination: image.url) {
                    Label("打开来源", systemImage: "safari")
                }
            }
            .accessibilityLabel("wallhaven-\(image.id)\(downloadedIDs.contains(image.id) ? "，已下载" : "")")
        }
    }

    private var localFilmstripCells: some View {
        ForEach(filteredItems) { item in
            FilmstripCell(isSelected: item.wallhavenID == currentLocalItem?.wallhavenID) {
                LocalImageView(url: item.fileURL, maxPixelSize: LayoutMetrics.filmstripLocalPixelSize)
                    .scaledToFill()
            }
            .id(item.wallhavenID)
            .onTapGesture {
                jumpToLocal(item.wallhavenID)
            }
            .contextMenu {
                Button {
                    QuickLookPreviewer.shared.show(url: item.fileURL)
                } label: {
                    Label("快速预览", systemImage: "eye")
                }

                Button {
                    setDesktopWallpaper(item)
                } label: {
                    Label("设为当前屏幕壁纸", systemImage: "desktopcomputer")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                } label: {
                    Label("在 Finder 中显示", systemImage: "folder")
                }

                Divider()

                Button(role: .destructive) {
                    pendingDeleteID = item.wallhavenID
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
            }
            .draggable(item.fileURL)
            .accessibilityLabel("wallhaven-\(item.wallhavenID)，\(item.resolution)")
        }
    }

    private func onlineEmptyActions(primaryTitle: String) -> some View {
        HStack(spacing: 8) {
            Button(primaryTitle) {
                Task { await loadPage(1, resetSeed: true) }
            }
            .buttonStyle(.borderedProminent)

            Button("调整筛选") {
                showOnlineFilters = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func onlineWarningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("重试") {
                Task { await loadPage(currentPage, append: currentPage > 1) }
            }

            Button {
                onlineErrorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("忽略此提示")
        }
        .font(.callout)
        .padding(10)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 当前项与逐张推进

    private var currentOnlineImage: WallhavenImage? {
        onlineBuffer.indices.contains(onlineIndex) ? onlineBuffer[onlineIndex] : nil
    }

    private var currentLocalItem: WallpaperItem? {
        let list = filteredItems
        return list.indices.contains(localIndex) ? list[localIndex] : nil
    }

    private var currentBrowseID: String? {
        switch mainMode {
        case .online:
            currentOnlineImage?.id
        case .gallery:
            currentLocalItem?.wallhavenID
        }
    }

    private var currentPurity: String? {
        switch mainMode {
        case .online:
            currentOnlineImage?.purity
        case .gallery:
            currentLocalItem?.purity
        }
    }

    private var currentResolution: String {
        switch mainMode {
        case .online:
            currentOnlineImage?.resolution ?? ""
        case .gallery:
            currentLocalItem?.resolution ?? ""
        }
    }

    private var currentCategory: String? {
        guard mainMode == .online else { return nil }
        return currentOnlineImage?.category.capitalized
    }

    private var currentFileSize: Int? {
        switch mainMode {
        case .online:
            return currentOnlineImage?.fileSize
        case .gallery:
            guard let size = currentLocalItem?.fileSize, size > 0 else { return nil }
            return size
        }
    }

    private var hasBrowseItems: Bool {
        mainMode == .online ? !onlineBuffer.isEmpty : !filteredItems.isEmpty
    }

    private var currentIndex: Int {
        mainMode == .online ? onlineIndex : localIndex
    }

    private var browseCount: Int {
        mainMode == .online ? onlineBuffer.count : filteredItems.count
    }

    private var canGoPrevious: Bool {
        currentIndex > 0
    }

    /// 在线还能续页时，末尾的「下一张」仍然可用。
    private var canGoNext: Bool {
        currentIndex + 1 < browseCount || (mainMode == .online && currentPage < lastPage)
    }

    private func advance(_ delta: Int) {
        switch mainMode {
        case .online:
            advanceOnline(delta)
        case .gallery:
            advanceLocal(delta)
        }
    }

    private func advanceOnline(_ delta: Int) {
        guard !onlineBuffer.isEmpty else { return }

        let target = onlineIndex + delta
        if target < 0 {
            statusText = "已经是第一张"
            return
        }
        if target < onlineBuffer.count {
            onlineIndex = target
            afterAdvance()
            return
        }
        guard delta > 0 else { return }

        if isLoading {
            statusText = "正在加载更多…"
            return
        }
        if currentPage < lastPage {
            pendingAdvance = true
            statusText = "正在加载更多…"
            Task { await loadPage(currentPage + 1, append: true) }
        } else {
            statusText = "已经是最后一张（共 \(totalCount) 张）"
        }
    }

    private func advanceLocal(_ delta: Int) {
        let count = filteredItems.count
        guard count > 0 else { return }

        let target = localIndex + delta
        if target < 0 {
            statusText = "已经是第一张"
            return
        }
        guard target < count else {
            statusText = "已经是最后一张（共 \(count) 张）"
            return
        }
        localIndex = target
    }

    /// 接近缓冲区末尾时静默续页；因为一次只展一张，追加不会造成布局跳动。
    private func afterAdvance() {
        guard mainMode == .online, !isLoading, currentPage < lastPage else { return }
        guard onlineIndex >= onlineBuffer.count - LayoutMetrics.loadMoreThreshold else { return }
        Task { await loadPage(currentPage + 1, append: true) }
    }

    private func jumpToOnline(_ id: String) {
        guard let index = onlineBuffer.firstIndex(where: { $0.id == id }) else { return }
        onlineIndex = index
        afterAdvance()
    }

    private func jumpToLocal(_ id: String) {
        guard let index = filteredItems.firstIndex(where: { $0.wallhavenID == id }) else { return }
        localIndex = index
    }

    private func toggleFavorite(_ item: WallpaperItem) {
        var tags = item.tags
        if tags.contains("favorite") {
            tags.removeAll { $0 == "favorite" }
        } else {
            tags.append("favorite")
        }
        item.tagsText = tags.joined(separator: ", ")
        try? modelContext.save()
    }

    // MARK: - 预取

    /// 当前项、解码尺寸、缓冲区长度任一变化都重新评估预取目标。
    private var prefetchKey: String {
        switch mainMode {
        case .online:
            "\(currentOnlineImage?.id ?? "-")|\(Int(stagePixelSize))|\(onlineBuffer.count)"
        case .gallery:
            "\(currentLocalItem?.wallhavenID ?? "-")|\(Int(stagePixelSize))|\(filteredItems.count)"
        }
    }

    /// 提前解码下一张，方向键切换基本无等待。
    private func prefetchNext() async {
        switch mainMode {
        case .online:
            let next = onlineIndex + 1
            guard next < onlineBuffer.count else { return }
            let image = onlineBuffer[next]
            _ = await RemoteImageLoader.load(url: image.path, maxPixelSize: stagePixelSize, referer: image.url)
        case .gallery:
            let list = filteredItems
            let next = localIndex + 1
            guard next < list.count else { return }
            _ = await LocalImageLoader.load(url: list[next].fileURL, maxPixelSize: stagePixelSize)
        }
    }

    // MARK: - 键盘导航

    /// 返回 true 表示按键已消费。长按方向键（isARepeat）一律放行，即连翻。
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad])

        if modifiers == .command {
            switch event.keyCode {
            case 18:
                mainMode = .online
                return true
            case 19:
                mainMode = .gallery
                return true
            default:
                return false
            }
        }
        guard modifiers.isEmpty else { return false }

        switch event.keyCode {
        case 123, 126:
            advance(-1)
            return true
        case 124, 125:
            advance(1)
            return true
        case 49:
            return performPrimaryAction()
        case 36:
            return performSecondaryAction()
        case 53:
            if isWallpaperPreviewing {
                isWallpaperPreviewing = false
                return true
            }
            if showOnlineFilters {
                showOnlineFilters = false
                return true
            }
            if showInspector {
                showInspector = false
                return true
            }
            return false
        default:
            return false
        }
    }

    private func performPrimaryAction() -> Bool {
        switch mainMode {
        case .online:
            guard let image = currentOnlineImage, !isDownloaded(image) else { return false }
            Task { await downloadImages([image]) }
            return true
        case .gallery:
            guard let item = currentLocalItem else { return false }
            setDesktopWallpaper(item)
            return true
        }
    }

    private func performSecondaryAction() -> Bool {
        switch mainMode {
        case .online:
            guard let image = currentOnlineImage else { return false }
            NSWorkspace.shared.open(image.url)
            return true
        case .gallery:
            guard let item = currentLocalItem else { return false }
            QuickLookPreviewer.shared.show(url: item.fileURL)
            return true
        }
    }

    /// 区分“图库为空”与“标签筛选无结果”，后者提供清除筛选的下一步。
    @ViewBuilder
    private var galleryEmptyState: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label("暂无壁纸", systemImage: "photo.on.rectangle")
            } description: {
                Text("在在线浏览中下载壁纸后会显示在这里")
            } actions: {
                Button("去在线浏览") {
                    mainMode = .online
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white.opacity(0.85))
        } else {
            ContentUnavailableView {
                Label("没有匹配的壁纸", systemImage: "magnifyingglass")
            } description: {
                Text("本地图库中没有标签包含“\(tagFilter)”的壁纸")
            } actions: {
                Button("清除筛选") {
                    tagFilter = ""
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if mainMode == .gallery, let selectedItem {
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
                    setDesktopWallpaper(selectedItem, allScreens: allScreens)
                },
                delete: {
                    pendingDeleteID = selectedItem.wallhavenID
                }
            )
        } else if mainMode == .online, let image = currentOnlineImage {
            OnlineDetailView(
                image: image,
                blurNSFW: blurNSFW,
                isDownloaded: isDownloaded(image),
                download: {
                    Task { await downloadImages([image]) }
                }
            )
        } else if mainMode == .online {
            inspectorPlaceholder(
                title: "暂无在线图片",
                message: "加载壁纸后，可在这里查看当前这张的完整信息与下载入口"
            )
        } else {
            inspectorPlaceholder(
                title: "选择一张本地壁纸",
                message: "可查看详情、编辑标签或设置为桌面壁纸"
            )
        }
    }

    /// 检查器空状态：窄列下自定义居中排版，避免图标与文案被压缩。
    private func inspectorPlaceholder(title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedItem: WallpaperItem? {
        guard let selectedID else { return nil }
        return items.first { $0.wallhavenID == selectedID }
    }

    private var pendingDeleteItem: WallpaperItem? {
        guard let pendingDeleteID else { return nil }
        return items.first { $0.wallhavenID == pendingDeleteID }
    }

    private var filteredItems: [WallpaperItem] {
        let query = tagFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return items }
        return items.filter { item in
            item.tags.contains { $0.lowercased().contains(query) }
        }
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
            apiKey: KeychainStore.loadAPIKey(),
            page: page,
            seed: effectiveSorting == .random ? randomSeed : nil
        )
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

    private func setDesktopWallpaper(_ item: WallpaperItem, allScreens: Bool = false) {
        do {
            try service.setDesktopWallpaper(item.fileURL, onAllScreens: allScreens)
            selectedID = item.wallhavenID
            statusText = allScreens ? "已设置为全部屏幕壁纸" : "已设置为当前屏幕壁纸"
        } catch {
            errorMessage = error.localizedDescription
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
                toggleFavorite(item)
            },
            select: { id in
                selectedID = id
                if let index = filteredItems.firstIndex(where: { $0.wallhavenID == id }) {
                    localIndex = index
                }
            }
        ))
    }

    /// append 为真时是自动续页，按 id 去重后追加到缓冲区且不动当前下标；
    /// 为假时是换来源 / 搜索 / 重试，缓冲区整个重建并回到第一张。
    @MainActor
    private func loadPage(_ page: Int, resetSeed: Bool = false, append: Bool = false) async {
        isLoading = true
        if !append { onlineErrorMessage = nil }
        statusText = append ? "正在加载更多…" : "正在加载 Wallhaven 第 \(page) 页"
        if resetSeed { randomSeed = nil }
        defer { isLoading = false }

        do {
            let result = try await service.search(searchOptions(page: page))
            if append {
                let existingIDs = Set(onlineBuffer.map(\.id))
                onlineBuffer.append(contentsOf: result.images.filter { !existingIDs.contains($0.id) })
            } else {
                onlineBuffer = result.images
                onlineIndex = 0
            }
            currentPage = result.meta.currentPage
            lastPage = max(1, result.meta.lastPage)
            totalCount = result.meta.total
            if sorting == .random || listing == .random {
                randomSeed = result.meta.seed
            }

            if pendingAdvance {
                pendingAdvance = false
                if onlineIndex + 1 < onlineBuffer.count {
                    onlineIndex += 1
                }
            }

            if append {
                statusText = "已续取第 \(result.meta.currentPage) 页，缓冲区 \(onlineBuffer.count) 张"
            } else {
                statusText = result.isFromCache ? "已从缓存加载 \(result.images.count) 张在线结果" : "已加载 \(result.images.count) 张在线结果"
            }
        } catch {
            onlineErrorMessage = error.localizedDescription
            pendingAdvance = false
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

/// 胶囊筛选按钮：补充 .plain 样式缺失的按下反馈。
private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

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
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(chipBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(ChipButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var chipBackground: Color {
        if isSelected { return Color.accentColor }
        return isHovered ? Color.primary.opacity(0.07) : Color(nsColor: .controlBackgroundColor)
    }
}

private struct ColorFilterChip: View {
    let option: WallhavenColorOption
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

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
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(chipBackground, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(ChipButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var chipBackground: Color {
        if isSelected { return Color.accentColor }
        return isHovered ? Color.primary.opacity(0.07) : Color(nsColor: .controlBackgroundColor)
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

/// 统一的缩略图容器：先按比例占位，再让图片填满并裁切，行高因此稳定。
private struct ThumbnailBox<Content: View>: View {
    let ratio: CGFloat
    let content: Content

    init(ratio: CGFloat = LayoutMetrics.thumbnailRatio, @ViewBuilder content: () -> Content) {
        self.ratio = ratio
        self.content = content()
    }

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { content }
            .clipShape(LayoutMetrics.cardShape)
            .contentShape(LayoutMetrics.cardShape)
    }
}

/// 缩略图条单元格：固定尺寸，选中态用 accent 描边，非选中态压暗以突出当前张。
private struct FilmstripCell<Content: View>: View {
    let isSelected: Bool
    let content: Content

    @State private var isHovered = false

    init(isSelected: Bool, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        ThumbnailBox { content }
            .frame(width: LayoutMetrics.filmstripCellWidth, height: LayoutMetrics.filmstripCellHeight)
            .overlay {
                LayoutMetrics.cardShape
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: isSelected ? 2.5 : 1)
            }
            .opacity(isSelected || isHovered ? 1 : 0.72)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

/// 在线图片的检查器：字段全部来自搜索响应，不发起额外请求。
private struct OnlineDetailView: View {
    let image: WallhavenImage
    let blurNSFW: Bool
    let isDownloaded: Bool
    let download: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewImage
                detailActions
                infoSection
            }
            .padding(14)
        }
    }

    private var previewImage: some View {
        ThumbnailBox {
            SensitiveImage(blurRadius: wallpaperBlurRadius(for: image.purity, enabled: blurNSFW)) {
                CachedRemoteImageView(url: image.path,
                                      maxPixelSize: LayoutMetrics.inspectorPreviewPixelSize,
                                      referer: image.url)
            }
        }
        .overlay(alignment: .topTrailing) {
            if image.purity.lowercased() != "sfw" {
                PurityBadge(purity: image.purity)
                    .padding(8)
            }
        }
        .overlay {
            LayoutMetrics.cardShape
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var detailActions: some View {
        VStack(spacing: 8) {
            Button(action: download) {
                Label(isDownloaded ? "已在本地图库" : "下载", systemImage: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDownloaded)

            Link(destination: image.url) {
                Label("打开来源页", systemImage: "safari")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("信息")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                infoRow("分辨率", value: image.resolution)
                infoRow("类型", value: image.purity.uppercased())
                infoRow("分类", value: image.category.capitalized)
                infoRow("大小", value: ByteCountFormatter.string(fromByteCount: Int64(image.fileSize), countStyle: .file))
                infoRow("ID", value: image.id, isSelectable: true)

                GridRow {
                    Text("来源")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Link("打开 Wallhaven 页面", destination: image.url)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func infoRow(_ label: String, value: String, isSelectable: Bool = false) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)

            infoValue(value, isSelectable: isSelectable)
        }
    }

    /// 仅 ID 这类需要复制的值开启文本选择。
    @ViewBuilder
    private func infoValue(_ value: String, isSelectable: Bool) -> some View {
        let text = Text(value)
            .font(.callout)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)

        if isSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }
}

/// 承载主窗口键盘导航的隐形视图：只在所属窗口内响应，且对文本输入与 sheet 让位。
private final class KeyCatcherView: NSView {
    var handler: ((NSEvent) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            guard window.attachedSheet == nil else { return event }
            // 文本框的字段编辑器是 NSTextView，方向键必须留给光标。
            guard !(window.firstResponder is NSTextView) else { return event }
            return self.handler?(event) == true ? nil : event
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

private struct KeyCatcher: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView(frame: .zero)
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {
        nsView.handler = handler
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previewImage
                wallpaperActions
                infoSection
                tagsSection

                Divider()

                Button(role: .destructive, action: delete) {
                    Label("移到废纸篓", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
        }
    }

    private var previewImage: some View {
        ThumbnailBox {
            SensitiveImage(blurRadius: wallpaperBlurRadius(for: item.purity, enabled: blurNSFW)) {
                LocalImageView(url: item.fileURL, maxPixelSize: 1400)
                    .scaledToFill()
            }
        }
        .overlay(alignment: .topTrailing) {
            if item.purity.lowercased() != "sfw" {
                PurityBadge(purity: item.purity)
                    .padding(8)
            }
        }
        .overlay {
            LayoutMetrics.cardShape
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        }
        .onTapGesture(count: 2, perform: preview)
        .help("双击快速预览")
    }

    /// 主动作（当前屏幕）突出，次级动作并排，删除独立到底部。
    private var wallpaperActions: some View {
        VStack(spacing: 8) {
            Button {
                setWallpaper(false)
            } label: {
                Label("设为壁纸", systemImage: "desktopcomputer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 8) {
                Button {
                    setWallpaper(true)
                } label: {
                    Label("全部屏幕", systemImage: "rectangle.on.rectangle")
                        .frame(maxWidth: .infinity)
                }

                Button(action: preview) {
                    Label("预览", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }

                Button(action: revealInFinder) {
                    Label("Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("信息")

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                infoRow("分辨率", value: item.resolution)
                infoRow("类型", value: item.purity.uppercased())
                infoRow("大小", value: ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))
                infoRow("下载时间", value: item.downloadedAt.formatted(date: .abbreviated, time: .shortened))
                infoRow("ID", value: item.wallhavenID, isSelectable: true)

                GridRow {
                    Text("来源")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Link("打开 Wallhaven 页面", destination: item.sourceURL)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func infoRow(_ label: String, value: String, isSelectable: Bool = false) -> some View {
        GridRow {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)

            infoValue(value, isSelectable: isSelectable)
        }
    }

    /// 仅 ID 这类需要复制的值开启文本选择。
    @ViewBuilder
    private func infoValue(_ value: String, isSelectable: Bool) -> some View {
        let text = Text(value)
            .font(.callout)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)

        if isSelectable {
            text.textSelection(.enabled)
        } else {
            text
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("标签")

            TextField("标签，用逗号分隔", text: $item.tagsText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)

            Text("用逗号分隔；favorite 会在图库显示星标")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct PurityBadge: View {
    let purity: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(purity.uppercased())
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Capsule())
        .accessibilityLabel("类型 \(purity.uppercased())")
    }

    /// 材质底 + 语义色圆点，比直接压在图上的彩色半透底更易读。
    private var dotColor: Color {
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
        .padding(.vertical, 3.5)
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
    /// 单图舞台背后是环境光模糊图，铺灰底会把它盖掉；缩略图与检查器仍需要占位底。
    var showsPlaceholderBackground = true
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else if showsPlaceholderBackground {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Color.clear
            }
        }
        .task(id: "\(url.path)-\(Int(maxPixelSize))") {
            image = await LocalImageLoader.load(url: url, maxPixelSize: maxPixelSize)
        }
    }
}
