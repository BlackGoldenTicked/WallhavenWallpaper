import AppKit
import SwiftData
import SwiftUI

/// 全局布局度量，避免各处重复的魔法数字。
private enum LayoutMetrics {
    static let cardCornerRadius: CGFloat = 12
    static let thumbnailRatio: CGFloat = 3 / 2
    /// 主图按舞台尺寸解码的上限，超过这个像素数对肉眼已无收益。
    static let heroMaxPixelCap: CGFloat = 2600
    static let ambientBlurRadius: CGFloat = 32
    static let ambientPixelSize: CGFloat = 120
    static let filmstripCellWidth: CGFloat = 144
    static let filmstripCellHeight: CGFloat = 96
    static let filmstripSpacing: CGFloat = 12
    /// 横向 ScrollView 在竖向上是贪婪的，不钉死高度会和舞台对分空间。
    static let filmstripHeight: CGFloat = 102
    static let filmstripRemotePixelSize: CGFloat = 220
    static let filmstripLocalPixelSize: CGFloat = 280
    /// 距缓冲区末尾还剩这么多张时开始静默续页。
    static let loadMoreThreshold = 3

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }
}

/// 主区两种模式：在线浏览与本地图库，共用同一套单图浏览器与方向键逻辑。
enum MainPaneMode: String, CaseIterable, Identifiable {
    case online
    case gallery

    var id: Self { self }

    var title: String {
        switch self {
        case .online: "在线浏览"
        case .gallery: "本地图库"
        }
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
    @AppStorage("rootPath") private var rootPath = WallhavenService.defaultRootDirectory.path
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
    /// 筛选抽屉草稿：应用前不写设置，取消即丢弃。
    @State private var draftOrderDescending = true
    @State private var draftTopRange: TopRange = .oneMonth
    @State private var draftResolutionMode: ResolutionMode = .atLeast
    @State private var draftResolution = "1920x1080"
    @State private var draftColor = ""
    @State private var draftIncludeGeneral = true
    @State private var draftIncludeAnime = true
    @State private var draftIncludePeople = false
    @State private var draftPurity: PurityFilter = .sfw
    @State private var draftRatios = "16x9,16x10"
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
        GeometryReader { rootProxy in
            VStack(spacing: 0) {
                ZStack {
                    heroStage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    stageScrims

                    VStack(spacing: 12) {
                        topNavBar

                        if mainMode == .online {
                            filterRow
                        
                            if let onlineErrorMessage, !onlineBuffer.isEmpty {
                                onlineWarningBanner(onlineErrorMessage)
                                    .transition(.opacity)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    // 顶栏控件按标题栏安全区高度下沉：壁纸铺到红绿灯行，控件位置不变。
                    .padding(.top, 16 + rootProxy.safeAreaInsets.top)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    if hasBrowseItems {
                        VStack(spacing: 16) {
                            Spacer(minLength: 0)

                            heroInfoBlock
                                .padding(.horizontal, 26)

                            if showFilmstrip {
                                filmstrip
                            }
                        }
                        .padding(.bottom, 14)
                    }
                    
                    // 箭头置于最顶层：窗口缩小时不被顶栏/信息块/缩略图条遮挡。
                    stageOverlays

                    // 筛选面板最上层：左扩竖排，覆盖舞台左侧。
                    if mainMode == .online && showOnlineFilters {
                        filterDrawerPanel(topInset: rootProxy.safeAreaInsets.top)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
                .onHover { isStageHovered = $0 }
                .animation(.easeInOut(duration: 0.22), value: showOnlineFilters)
                .clipped()

                Divider()

                statusBar
            }
            // 舞台与顶部渐变伸入标题栏安全区，红绿灯直接浮在壁纸上，整窗浑然一体。
            .ignoresSafeArea(edges: .top)
        }
        .background(KeyCatcher(handler: handleKey))
        .overlay {
            wallpaperPreviewLayer
                .animation(.easeOut(duration: 0.18), value: isWallpaperPreviewing)
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
        .onChange(of: filteredItems.count) { _, count in
            localIndex = min(localIndex, max(0, count - 1))
        }
        .onChange(of: showOnlineFilters) { _, showing in
            if showing { syncFilterDrafts() }
        }
        .onChange(of: mainMode) { _, mode in
            if mode == .online && onlineBuffer.isEmpty && !isLoading {
                Task { await loadPage(1) }
            }
        }
        .task {
            // 首启进入在线浏览直接自动加载，不停在空状态。
            if mainMode == .online && onlineBuffer.isEmpty && !isLoading {
                await loadPage(1)
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
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(2)

            Text(positionText)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            Text(keyboardHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                HStack {
                    Spacer()

                    Button {
                        isWallpaperPreviewing = false
                    } label: {
                        navCircle(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("退出预览 (Esc)")
                }
                .padding(14)

                Spacer()

                previewControlBar
                    .padding(.bottom, 26)
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

    /// 全屏预览底部悬浮胶囊条：信息 + 动作 + 退出，对应 Wallspace 全屏预览底栏。
    private var previewControlBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("wallhaven-\(currentBrowseID ?? "")")
                    .font(.body.weight(.semibold))
                Text(previewCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 24)

            switch mainMode {
            case .online:
                if let image = currentOnlineImage {
                    Button {
                        Task { await downloadImages([image]) }
                    } label: {
                        navCircle(systemName: "arrow.down.circle", size: 36)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloaded(image))
                    .help("下载")
                }
            case .gallery:
                if let item = currentLocalItem {
                    Button {
                        setDesktopWallpaper(item)
                    } label: {
                        navCircle(systemName: "desktopcomputer", size: 36)
                    }
                    .buttonStyle(.plain)
                    .help("设为壁纸")
                }
            }

            Button {
                isWallpaperPreviewing = false
            } label: {
                Text("退出预览")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    private var previewCaption: String {
        switch mainMode {
        case .online:
            guard let image = currentOnlineImage else { return "" }
            return "\(image.resolution) · \(ByteCountFormatter.string(fromByteCount: Int64(image.fileSize), countStyle: .file))"
        case .gallery:
            guard let item = currentLocalItem else { return "" }
            let size = item.fileSize > 0
                ? " · \(ByteCountFormatter.string(fromByteCount: Int64(item.fileSize), countStyle: .file))"
                : ""
            return "\(item.resolution)\(size)"
        }
    }

    // MARK: - 顶部筛选表单

    /// 顶部导航悬浮在舞台上方：模式胶囊居中，玻璃圆按钮靠右（Wallspace 式顶栏）。
    private var topNavBar: some View {
        HStack {
            Spacer(minLength: 0)
            modePicker
            Spacer(minLength: 0)
        }
        .overlay(alignment: .trailing) { navButtons }
    }

    private var navButtons: some View {
        HStack(spacing: 8) {
            Button {
                isWallpaperPreviewing.toggle()
            } label: {
                navCircle(systemName: "desktopcomputer", filled: isWallpaperPreviewing)
            }
            .buttonStyle(.plain)
            .help(isWallpaperPreviewing ? "退出桌面预览" : "桌面壁纸预览")
            .disabled(currentBrowseID == nil)

            Button {
                showFilmstrip.toggle()
            } label: {
                navCircle(systemName: "film", filled: showFilmstrip)
            }
            .buttonStyle(.plain)
            .help(showFilmstrip ? "隐藏缩略图条" : "显示缩略图条")

            SettingsLink {
                navCircle(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("设置")
        }
    }

    /// 玻璃圆按钮标签：图上操作的主控件语言，SettingsLink 与 Button 共用。
    private func navCircle(systemName: String, filled: Bool = false, size: CGFloat = 34) -> some View {
        Image(systemName: systemName)
            .symbolVariant(filled ? .fill : .none)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: size, height: size)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
            }
    }

    /// 模式切换：玻璃胶囊内的白-pill 分段，选中项反白。
    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(MainPaneMode.allCases) { mode in
                Button {
                    mainMode = mode
                } label: {
                    Text(mode.title)
                        .font(.body.weight(mainMode == mode ? .semibold : .regular))
                        .foregroundStyle(mainMode == mode ? Color.black : Color.white.opacity(0.85))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(mainMode == mode ? Color.white : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .help(mode.title)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    /// 筛选区两行左对齐：类别胶囊行 + 动作胶囊行（抽屉在其下展开），水平间距统一。
    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                listingSelector

                if listing == .search {
                    queryField
                        .frame(minWidth: 180, idealWidth: 280, maxWidth: 360)
                }

                Spacer(minLength: 0)
            }

            onlineActions
        }
    }

    /// 动作胶囊行：筛选/加载与类别行同款玻璃胶囊，左对齐等间距。
    private var onlineActions: some View {
        HStack(spacing: 12) {
            Button {
                showOnlineFilters.toggle()
            } label: {
                stagePill {
                    Label("筛选", systemImage: "line.3.horizontal.decrease")
                        .symbolVariant(showOnlineFilters ? .fill : .none)
                }
            }
            .buttonStyle(.plain)
            .help(showOnlineFilters ? "收起筛选" : "展开筛选")

            Button {
                guard !isLoading else { return }
                Task { await loadPage(1, resetSeed: true) }
            } label: {
                stagePill {
                    Label(isLoading ? "加载中" : primaryActionTitle, systemImage: listing == .search ? "magnifyingglass" : "arrow.clockwise")
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.plain)
        }
    }

    /// 图上胶囊标签：类别与动作行共用的 pill 语言（深色玻璃胶囊 + 图标文字）。
    private func stagePill<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body.weight(.medium))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var downloadedIDs: Set<String> {
        Set(items.map(\.wallhavenID))
    }

    private func isDownloaded(_ image: WallhavenImage?) -> Bool {
        guard let image else { return false }
        return downloadedIDs.contains(image.id)
    }

    /// 来源胶囊按钮行：玻璃胶囊 + 图标，选中反白，左对齐等间距（参考图样式）。
    private var listingSelector: some View {
        HStack(spacing: 12) {
            ForEach(WallhavenListing.allCases) { item in
                Button {
                    listing = item
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .font(.body.weight(listing == item ? .semibold : .medium))
                        .foregroundStyle(listing == item ? Color.black : Color.white.opacity(0.92))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(listing == item ? AnyShapeStyle(Color.white) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
        }
        .onChange(of: listing) { _, item in
            sorting = item.defaultSorting
            currentPage = 1
            randomSeed = nil
            onlineErrorMessage = nil
            if item != .search {
                query = ""
                // 切换类别即以默认筛选自动加载；社区搜索保持手动提交。
                resetFiltersToDefaults()
                Task { await loadPage(1, resetSeed: true) }
            }
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

    /// 左扩竖排筛选面板：参考截图 UI/UX；草稿编辑，应用后才写设置并重新加载。
    private func filterDrawerPanel(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            drawerHeader
                .padding(.top, topInset)
                .overlay(alignment: .bottom) { Divider() }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    sectionCard("排序", systemImage: "arrow.up.arrow.down", value: drawerSortingSummary) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("排序", selection: $draftOrderDescending) {
                                Label("倒序", systemImage: "arrow.down").tag(true)
                                Label("正序", systemImage: "arrow.up").tag(false)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            if sorting == .toplist {
                                HStack(spacing: 12) {
                                    Slider(value: draftTopRangeSliderValue, in: 0...Double(TopRange.allCases.count - 1), step: 1)
                                    Text(draftTopRange.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                        .frame(width: 52, alignment: .leading)
                                }
                            }
                        }
                    }

                    sectionCard("分辨率", systemImage: "display", value: drawerResolutionSummary) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("匹配", selection: $draftResolutionMode) {
                                ForEach(ResolutionMode.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)

                            WrappingHStack(spacing: 8, rowSpacing: 8) {
                                ForEach(resolutionOptions, id: \.value) { option in
                                    DrawerChip(title: option.title, isSelected: draftResolution == option.value) {
                                        draftResolution = option.value
                                    }
                                }
                            }
                        }
                    }

                    sectionCard("颜色", systemImage: "paintpalette", value: drawerColorSummary) {
                        WrappingHStack(spacing: 8, rowSpacing: 8) {
                            DrawerChip(title: "不限", isSelected: draftColor.isEmpty) {
                                draftColor = ""
                            }
                            ForEach(wallhavenColorOptions) { option in
                                ColorSwatch(color: option.color, name: option.name, isSelected: draftColor == option.value) {
                                    draftColor = option.value
                                }
                            }
                        }
                    }

                    sectionCard("内容", systemImage: "checkmark.shield", value: "已选 \([draftIncludeGeneral, draftIncludeAnime, draftIncludePeople].filter { $0 }.count) 项") {
                        VStack(alignment: .leading, spacing: 10) {
                            WrappingHStack(spacing: 8, rowSpacing: 8) {
                                DrawerChip(title: "General", isSelected: draftIncludeGeneral) { draftIncludeGeneral.toggle() }
                                DrawerChip(title: "Anime", isSelected: draftIncludeAnime) { draftIncludeAnime.toggle() }
                                DrawerChip(title: "People", isSelected: draftIncludePeople) { draftIncludePeople.toggle() }
                            }

                            WrappingHStack(spacing: 8, rowSpacing: 8) {
                                ForEach(PurityFilter.allCases) { option in
                                    if option != .all || allowNSFW {
                                        DrawerChip(title: option.title, isSelected: draftPurity == option) {
                                            draftPurity = option
                                        }
                                    }
                                }
                            }

                            // 设置页「筛选」面板已移除，NSFW 开关归位到此处统一配置。
                            Toggle("允许 NSFW", isOn: $allowNSFW)
                                .toggleStyle(.switch)
                                .onChange(of: allowNSFW) { _, isAllowed in
                                    if !isAllowed {
                                        purity = .sfw
                                        draftPurity = .sfw
                                    }
                                }

                            if allowNSFW {
                                Toggle("Sketchy / NSFW 默认模糊", isOn: $blurNSFW)
                                    .toggleStyle(.switch)
                            }
                        }
                    }

                    sectionCard("比例", systemImage: "rectangle.inset.filled", value: drawerRatioSummary) {
                        // ratioOptions 首项已是「不限」（空值），不再另加芯片。
                        WrappingHStack(spacing: 8, rowSpacing: 8) {
                            ForEach(ratioOptions, id: \.value) { option in
                                DrawerChip(title: option.title, isSelected: draftRatios == option.value) {
                                    draftRatios = option.value
                                }
                            }
                        }
                    }
                }
                .padding(14)
            }

            drawerFooter
                .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 面板顶栏：标题、已选计数、重置与关闭（对应截图头部）。
    private var drawerHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text("筛选条件")
                .font(.title3.weight(.semibold))

            if selectedFilterCount > 0 {
                Text("已选 \(selectedFilterCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.35), in: Capsule())
            }

            Spacer()

            Button("重置") { resetFilterDrafts() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("恢复默认筛选")

            Button {
                showOnlineFilters = false
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("关闭筛选 (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// 面板底栏：结果数、取消与应用（对应截图底部）。
    private var drawerFooter: some View {
        HStack(spacing: 10) {
            Text("共 \(totalCount) 个结果")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button("取消") { showOnlineFilters = false }
                .buttonStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08), in: Capsule())

            Button {
                applyFilterDrafts()
            } label: {
                Label("应用筛选", systemImage: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// 筛选卡片：标题 + 当前值摘要在上、控件在下（对应截图卡片）。
    private func sectionCard<Content: View>(_ title: String, systemImage: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.body.weight(.semibold))

                Spacer()

                Text(value)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var drawerSortingSummary: String {
        var text = "\(sorting.title) · \(draftOrderDescending ? "倒序" : "正序")"
        if sorting == .toplist {
            text += " · \(draftTopRange.title)"
        }
        return text
    }

    private var drawerResolutionSummary: String {
        let res = resolutionOptions.first { $0.value == draftResolution }?.title ?? "不限"
        return "\(draftResolutionMode.title) · \(res)"
    }

    private var drawerColorSummary: String {
        wallhavenColorOptions.first { $0.value == draftColor }?.name ?? "不限"
    }

    private var drawerRatioSummary: String {
        ratioOptions.first { $0.value == draftRatios }?.title ?? "不限"
    }

    /// 草稿中生效的筛选项计数，供顶栏徽章。
    private var selectedFilterCount: Int {
        var count = [draftIncludeGeneral, draftIncludeAnime, draftIncludePeople].filter { $0 }.count
        if !draftResolution.isEmpty { count += 1 }
        if !draftColor.isEmpty { count += 1 }
        if !draftRatios.isEmpty { count += 1 }
        if draftPurity != .sfw { count += 1 }
        return count
    }

    private func syncFilterDrafts() {
        draftOrderDescending = orderDescending
        draftTopRange = topRange
        draftResolutionMode = resolutionMode
        draftResolution = resolution
        draftColor = color
        draftIncludeGeneral = includeGeneral
        draftIncludeAnime = includeAnime
        draftIncludePeople = includePeople
        draftPurity = purity
        draftRatios = ratios
    }

    /// 应用：草稿写回设置、关面板并重载第一页。
    private func applyFilterDrafts() {
        orderDescending = draftOrderDescending
        topRange = draftTopRange
        resolutionMode = draftResolutionMode
        resolution = draftResolution
        color = draftColor
        includeGeneral = draftIncludeGeneral
        includeAnime = draftIncludeAnime
        includePeople = draftIncludePeople
        purity = draftPurity
        ratios = draftRatios
        showOnlineFilters = false
        Task { await loadPage(1, resetSeed: true) }
    }

    private func resetFilterDrafts() {
        draftOrderDescending = true
        draftTopRange = .oneMonth
        draftResolutionMode = .atLeast
        draftResolution = "1920x1080"
        draftColor = ""
        draftIncludeGeneral = true
        draftIncludeAnime = true
        draftIncludePeople = false
        draftPurity = .sfw
        draftRatios = "16x9,16x10"
    }

    /// 切换类别 / 空结果回退时恢复默认筛选，保证各类型都有结果可载。
    private func resetFiltersToDefaults() {
        orderDescending = true
        topRange = .oneMonth
        resolutionMode = .atLeast
        resolution = "1920x1080"
        color = ""
        includeGeneral = true
        includeAnime = true
        includePeople = false
        purity = .sfw
        ratios = "16x9,16x10"
    }

    private var draftTopRangeSliderValue: Binding<Double> {
        Binding(
            get: { Double(TopRange.allCases.firstIndex(of: draftTopRange) ?? 0) },
            set: { value in
                let index = max(0, min(TopRange.allCases.count - 1, Int(value.rounded())))
                draftTopRange = TopRange.allCases[index]
            }
        )
    }

    /// 搜索框：与类别胶囊同款深色玻璃胶囊，内边距/字号一致，高度对齐。
    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.6))

            TextField("关键词 / 标签 / id:123 / @用户", text: $query)
                .textFieldStyle(.plain)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.92))
                .onSubmit { submitOnlineSearch() }

            if !query.isEmpty {
                Button {
                    query = ""
                    submitOnlineSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.5))
                .help("清空关键词")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
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
                    // 钉死主图容器并裁切：fill 图会上报超尺寸，不居中裁切会整体偏移露出左侧灰底。
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    // 切换动画只作用于主图，避免连带驱动悬浮箭头产生闪现/半显。
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: currentBrowseID)
            }
            // 钉死舞台尺寸：fill 图片会按自身宽高比上报超出舞台的尺寸，
            // 一旦撑大 ZStack，GeometryReader 的 topLeading 布局 + 居中对齐
            // 会让主图整体偏移、左侧露出背景灰（宽图切换时概率复现）。
            .frame(width: proxy.size.width, height: proxy.size.height)
            .preferredColorScheme(.dark)
            .onAppear { stagePixelSize = heroPixelSize(for: proxy.size) }
            .onChange(of: proxy.size) { _, newSize in
                stagePixelSize = heroPixelSize(for: newSize)
            }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// 舞台上下局部渐变：保证悬浮控件可读，又不在整张图上蒙均匀黑幕。
    @ViewBuilder
    private var stageScrims: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.66), Color.black.opacity(0.32), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 230)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)

        if hasBrowseItems {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.42), Color.black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 300)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        }
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
                    contentMode: .fill,
                    referer: image.url,
                    loadingHint: "正在加载原图"
                )
            }
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
                    .scaledToFill()
            }
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
        } else if listing == .search {
            ContentUnavailableView {
                Label("暂无在线结果", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("从 \(listing.title) 加载壁纸，或调整筛选条件后重试")
            } actions: {
                onlineEmptyActions(primaryTitle: primaryActionTitle)
            }
            .foregroundStyle(.white.opacity(0.85))
        } else {
            // 非搜索类别不展示空状态：加载链路会自动以默认筛选兜底，此处仅瞬时过渡。
            stageProgress("正在以默认筛选加载 Wallhaven")
        }
    }

    private func stageProgress(_ text: String) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)

            Text(text)
                .font(.body)
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
            // 钉死铺满舞台：箭头始终垂直居中、贴左右边缘，不随窗口尺寸或 ZStack 子视图尺寸漂移/被裁。
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isStageHovered ? 1 : 0)
            .animation(.easeOut(duration: 0.16), value: isStageHovered)
            .allowsHitTesting(isStageHovered)
        }
    }

    private func stageArrow(systemName: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.white.opacity(disabled ? 0.3 : 0.9))
                .frame(width: 52, height: 52)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    /// 左下信息块：徽章、编号、meta 与动作悬浮在底部渐变上（Wallspace 首页 hero 布局）。
    private var heroInfoBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let currentPurity, currentPurity.lowercased() != "sfw" {
                    PurityBadge(purity: currentPurity)
                }

                if mainMode == .online, isDownloaded(currentOnlineImage) {
                    MetadataBadge(title: "已下载", systemImage: "checkmark.circle.fill")
                }
            }

            Text("wallhaven-\(currentBrowseID ?? "")")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack(spacing: 12) {
                Text(currentResolution)
                if let currentCategory { Text(currentCategory) }
                if let currentFileSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(currentFileSize), countStyle: .file))
                }
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.white.opacity(0.72))

            heroActions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 图上动作：白-pill 主按钮 + 玻璃圆次按钮，替代原先的 bordered 按钮。
    @ViewBuilder
    private var heroActions: some View {
        switch mainMode {
        case .online:
            if let image = currentOnlineImage {
                HStack(spacing: 10) {
                    Button {
                        Task { await downloadImages([image]) }
                    } label: {
                        Label(isDownloaded(image) ? "已下载" : "下载",
                              systemImage: isDownloaded(image) ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloaded(image) || isLoading)

                    // 下载完成后才出现：设为壁纸依赖本地文件。
                    if isDownloaded(image) {
                        Button {
                            setDownloadedImageAsWallpaper(image)
                        } label: {
                            Label("设为壁纸", systemImage: "desktopcomputer")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("设为当前屏幕壁纸")
                    }

                    Link(destination: image.url) {
                        navCircle(systemName: "safari", size: 36)
                    }
                    .help("打开来源页")
                }
            }
        case .gallery:
            if let item = currentLocalItem {
                HStack(spacing: 10) {
                    Button {
                        setDesktopWallpaper(item)
                    } label: {
                        Label("设为壁纸", systemImage: "desktopcomputer")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        QuickLookPreviewer.shared.show(url: item.fileURL)
                    } label: {
                        navCircle(systemName: "eye", size: 36)
                    }
                    .buttonStyle(.plain)
                    .help("快速预览")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
                    } label: {
                        navCircle(systemName: "folder", size: 36)
                    }
                    .buttonStyle(.plain)
                    .help("在 Finder 中显示")
                }
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
                .padding(.horizontal, 24)
            }
            .frame(height: LayoutMetrics.filmstripHeight)
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
                    // 缩略图条不带揭示按钮，敏感图仅按设置模糊。
                    .blur(radius: wallpaperBlurRadius(for: image.purity, enabled: blurNSFW))
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
                    .blur(radius: wallpaperBlurRadius(for: item.purity, enabled: blurNSFW))
            }
            .id(item.wallhavenID)
            // 不加 .draggable：其拖拽交互会吞掉单击，导致点击缩略图无法切换（拖拽仍保留在主图上）。
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
        .font(.body)
        .padding(12)
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

    private var galleryEmptyState: some View {
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
    }

    private var pendingDeleteItem: WallpaperItem? {
        guard let pendingDeleteID else { return nil }
        return items.first { $0.wallhavenID == pendingDeleteID }
    }

    /// 标签筛选移除后，本地图库直接展示全部已下载项。
    private var filteredItems: [WallpaperItem] {
        items
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
            statusText = allScreens ? "已设置为全部屏幕壁纸" : "已设置为当前屏幕壁纸"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 已下载的在线图设为壁纸：按 wallhaven ID 定位本地条目后复用图库逻辑。
    private func setDownloadedImageAsWallpaper(_ image: WallhavenImage) {
        guard let item = items.first(where: { $0.wallhavenID == image.id }) else { return }
        setDesktopWallpaper(item)
    }

    /// append 为真时是自动续页，按 id 去重后追加到缓冲区且不动当前下标；
    /// 为假时是换来源 / 搜索 / 重试，缓冲区整个重建并回到第一张。
    @MainActor
    private func loadPage(_ page: Int, resetSeed: Bool = false, append: Bool = false, allowDefaultFallback: Bool = true) async {
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

            // 非搜索类别空结果时回退默认筛选再试一次，避免停在空状态。
            if !append, result.images.isEmpty, listing != .search, allowDefaultFallback {
                resetFiltersToDefaults()
                await loadPage(page, resetSeed: resetSeed, allowDefaultFallback: false)
                return
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

/// 抽屉圆角矩形芯片：选中态用 accent 描边 + 淡底（参考截图样式）。
private struct DrawerChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .font(.footnote.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.8))
                .background(isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

/// 主色调色块：圆角色块、选中白描边（参考截图样式）。
private struct ColorSwatch: View {
    let color: Color
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .frame(width: 34, height: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.15),
                                      lineWidth: isSelected ? 2 : 0.5)
                }
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
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
                    .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.2),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .opacity(isSelected ? 1 : (isHovered ? 0.9 : 0.55))
            .scaleEffect(isSelected ? 1.04 : 1)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isSelected)
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

struct PurityBadge: View {
    let purity: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(purity.uppercased())
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
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
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
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
