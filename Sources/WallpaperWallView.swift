import AppKit
import SwiftUI

struct WallpaperWallItem: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let purity: String
    let resolution: String
    let tags: [String]

    init(item: WallpaperItem) {
        id = item.wallhavenID
        fileURL = item.fileURL
        purity = item.purity
        resolution = item.resolution
        tags = item.tags
    }
}

enum MainPaneMode: String, CaseIterable, Identifiable {
    case online
    case gallery
    case configuration

    var id: Self { self }

    var title: String {
        switch self {
        case .online: "在线结果"
        case .gallery: "本地图库"
        case .configuration: "配置"
        }
    }

    var systemImage: String {
        switch self {
        case .online: "globe"
        case .gallery: "photo.on.rectangle"
        case .configuration: "gearshape"
        }
    }
}

struct WallpaperWallView: View {
    let items: [WallpaperWallItem]
    let blurNSFW: Bool
    let close: () -> Void
    let setWallpaper: (WallpaperWallItem) -> Bool
    let toggleFavoriteAction: (String) -> Void
    let select: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedID: String?
    @State private var hoveredID: String?
    @State private var density: CGFloat = 300
    @State private var statusText = ""
    @State private var keyMonitor: Any?

    private var focusedItem: WallpaperWallItem? {
        guard let focusedID else { return nil }
        return items.first { $0.id == focusedID }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                ScrollViewReader { reader in
                    ScrollView {
                        JustifiedWall(
                            items: items,
                            width: max(360, proxy.size.width - 48),
                            targetHeight: density,
                            spacing: spacing
                        ) { item, size in
                            WallCard(
                                item: item,
                                size: size,
                                blurNSFW: blurNSFW,
                                isHovered: hoveredID == item.id,
                                hover: { hovering in
                                    hoveredID = hovering ? item.id : nil
                                },
                                tap: {
                                    focus(item)
                                }
                            )
                            .id(item.id)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 74)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: focusedID) { _, id in
                        guard let id else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                            reader.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }

            topBar

            if let focusedItem {
                FocusOverlay(
                    item: focusedItem,
                    blurNSFW: blurNSFW,
                    statusText: statusText,
                    close: {
                        focusedID = nil
                        statusText = ""
                    },
                    previous: previous,
                    next: next,
                    favorite: {
                        toggleFavoriteAction(focusedItem.id)
                    },
                    setWallpaper: {
                        if setWallpaper(focusedItem) {
                            statusText = "已设置"
                            clearStatusLater()
                        }
                    }
                )
                .transition(.opacity)
            }

            if items.isEmpty {
                ContentUnavailableView("暂无壁纸", systemImage: "photo.on.rectangle", description: Text("下载后再进入壁纸墙"))
                    .foregroundStyle(.white.opacity(0.85))
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: focusedID)
        .onAppear {
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var topBar: some View {
        VStack {
            HStack(spacing: 14) {
                Button(action: close) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.82))

                Text("精选壁纸")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                Text("\(items.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.48))

                Spacer()

                Text("ESC 退出")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))

                Slider(value: $density, in: 180...420, step: 4)
                    .frame(width: 150)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.black.opacity(0.36), in: Capsule())
            .padding(.top, 18)

            Spacer()
        }
    }

    private var spacing: CGFloat {
        density < 240 ? 12 : 18
    }

    private func focus(_ item: WallpaperWallItem) {
        focusedID = item.id
        select(item.id)
    }

    private func previous() {
        moveFocus(-1)
    }

    private func next() {
        moveFocus(1)
    }

    private func moveFocus(_ delta: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = focusedID.flatMap { id in
            items.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex = (currentIndex + delta + items.count) % items.count
        focus(items[nextIndex])
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard WallpaperWallWindowController.shared.owns(event.window) else {
                return event
            }
            return handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            if focusedID == nil {
                close()
            } else {
                focusedID = nil
            }
            return true
        case 123:
            previous()
            return true
        case 124:
            next()
            return true
        case 49:
            if focusedID == nil, let first = items.first {
                focus(first)
            } else {
                focusedID = nil
            }
            return true
        case 36:
            if let focusedItem {
                if setWallpaper(focusedItem) {
                    statusText = "已设置"
                    clearStatusLater()
                }
            }
            return true
        default:
            return false
        }
    }

    private func clearStatusLater() {
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                statusText = ""
            }
        }
    }
}

private struct JustifiedWall<Content: View>: View {
    let items: [WallpaperWallItem]
    let width: CGFloat
    let targetHeight: CGFloat
    let spacing: CGFloat
    let content: (WallpaperWallItem, CGSize) -> Content

    var body: some View {
        LazyVStack(alignment: .leading, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { index in
                HStack(spacing: spacing) {
                    ForEach(rows[index].items, id: \.id) { item in
                        let size = rows[index].size(for: item)
                        content(item, size)
                            .frame(width: size.width, height: size.height)
                    }
                }
            }
        }
    }

    private var rows: [WallRow] {
        var rows: [WallRow] = []
        var rowItems: [WallpaperWallItem] = []
        var ratioSum: CGFloat = 0

        for item in items {
            rowItems.append(item)
            ratioSum += item.wallAspectRatio
            let naturalWidth = ratioSum * targetHeight + CGFloat(max(0, rowItems.count - 1)) * spacing
            if naturalWidth >= width {
                rows.append(WallRow(items: rowItems, width: width, targetHeight: targetHeight, spacing: spacing, justify: true))
                rowItems = []
                ratioSum = 0
            }
        }

        if !rowItems.isEmpty {
            rows.append(WallRow(items: rowItems, width: width, targetHeight: targetHeight, spacing: spacing, justify: rows.isEmpty))
        }
        return rows
    }
}

private struct WallRow {
    let items: [WallpaperWallItem]
    let width: CGFloat
    let targetHeight: CGFloat
    let spacing: CGFloat
    let justify: Bool

    func size(for item: WallpaperWallItem) -> CGSize {
        let height = rowHeight
        return CGSize(width: height * item.wallAspectRatio, height: height)
    }

    private var rowHeight: CGFloat {
        guard justify else { return targetHeight }
        let ratioSum = items.reduce(CGFloat.zero) { $0 + $1.wallAspectRatio }
        let contentWidth = width - CGFloat(max(0, items.count - 1)) * spacing
        return max(180, min(420, contentWidth / max(0.1, ratioSum)))
    }
}

private struct WallCard: View {
    let item: WallpaperWallItem
    let size: CGSize
    let blurNSFW: Bool
    let isHovered: Bool
    let hover: (Bool) -> Void
    let tap: () -> Void

    var body: some View {
        SensitiveImage(blurRadius: wallpaperBlurRadius(for: item.purity, enabled: blurNSFW)) {
            LocalImageView(url: item.fileURL, maxPixelSize: size.width > 380 ? 1100 : 720)
                .scaledToFill()
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .brightness(isHovered ? 0.05 : 0)
        .scaleEffect(isHovered ? 1.012 : 1)
        .shadow(color: .black.opacity(isHovered ? 0.32 : 0.18), radius: isHovered ? 18 : 7, y: isHovered ? 12 : 4)
        .overlay(alignment: .bottom) {
            if isHovered {
                HStack {
                    Text("wallhaven-\(item.id)")
                        .lineLimit(1)
                    Spacer()
                    Text(item.resolution)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onHover(perform: hover)
        .onTapGesture(perform: tap)
        .animation(.easeOut(duration: 0.14), value: isHovered)
    }

    private var cornerRadius: CGFloat {
        size.height > 210 ? 14 : 10
    }
}

private struct FocusOverlay: View {
    let item: WallpaperWallItem
    let blurNSFW: Bool
    let statusText: String
    let close: () -> Void
    let previous: () -> Void
    let next: () -> Void
    let favorite: () -> Void
    let setWallpaper: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            SensitiveImage(blurRadius: wallpaperBlurRadius(for: item.purity, enabled: blurNSFW)) {
                LocalImageView(url: item.fileURL, maxPixelSize: 2200)
                    .scaledToFit()
            }
            .padding(.horizontal, 72)
            .padding(.vertical, 70)

            HStack {
                Button(action: previous) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 42, weight: .light))
                        .frame(width: 90, height: 180)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))

                Spacer()

                Button(action: next) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 42, weight: .light))
                        .frame(width: 90, height: 180)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 18)

            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button(action: favorite) {
                        Label("收藏", systemImage: item.tags.contains("favorite") ? "heart.fill" : "heart")
                    }
                    Button(action: setWallpaper) {
                        Label(statusText.isEmpty ? "设置为壁纸" : statusText, systemImage: statusText.isEmpty ? "desktopcomputer" : "checkmark.circle")
                    }
                    Button(action: close) {
                        Label("返回", systemImage: "xmark")
                    }
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 28)
            }
        }
    }
}

private struct KeyEventReader: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyEventView, context: Context) {
        nsView.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyEventView: NSView {
    var onKeyDown: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }
}

private extension WallpaperWallItem {
    var wallAspectRatio: CGFloat {
        let parts = resolution.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              height > 0 else {
            return 16 / 9
        }
        return CGFloat(width / height)
    }
}
