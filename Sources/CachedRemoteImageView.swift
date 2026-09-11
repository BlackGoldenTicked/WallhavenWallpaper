import AppKit
import ImageIO
import SwiftUI

/// 远程图片的完整加载链路：内存缓存 → 磁盘缓存 → 网络 → 降采样解码 → 回写两级缓存。
/// 视图与预取共用，避免逻辑重复。
enum RemoteImageLoader {
    static func load(url: URL, maxPixelSize: CGFloat, referer: URL? = nil) async -> NSImage? {
        let key = cacheKey(url: url, maxPixelSize: maxPixelSize)
        if let cachedImage = RemoteImageMemoryCache.shared.image(for: key) {
            return cachedImage
        }

        do {
            let data: Data
            if let cachedData = try await AppCacheStore.shared.cachedThumbnailData(for: url) {
                data = cachedData
            } else {
                data = try await fetch(url: url, referer: referer)
                try await AppCacheStore.shared.storeThumbnailData(data, for: url)
            }

            guard let decoded = await decode(data, maxPixelSize: maxPixelSize) else { return nil }
            RemoteImageMemoryCache.shared.set(decoded.image, for: key, cost: decoded.pixelBytes)
            return decoded.image
        } catch {
            return nil
        }
    }

    /// 同一 URL 的不同解码尺寸必须分开缓存，否则互相污染。
    static func cacheKey(url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)@\(Int(maxPixelSize))"
    }

    private static func fetch(url: URL, referer: URL?) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) WallhavenWallpaper/1.0", forHTTPHeaderField: "User-Agent")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw WallpaperError.badHTTPStatus(httpResponse.statusCode)
        }
        return data
    }

    /// 缓存成本按解码后字节数计，压缩体积会严重低估原图占用。
    private static func decode(_ data: Data, maxPixelSize: CGFloat) async -> (image: NSImage, pixelBytes: Int)? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]

            if let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) {
                let thumbnailOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
                ]
                if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
                    // 必须带真实像素尺寸：size 为 .zero 会丢掉固有宽高比，.fit 模式下会退化成不可见。
                    let size = NSSize(width: cgImage.width, height: cgImage.height)
                    return (NSImage(cgImage: cgImage, size: size), cgImage.width * cgImage.height * 4)
                }
            }

            guard let fallback = NSImage(data: data) else { return nil }
            return (fallback, pixelBytes(of: fallback))
        }.value
    }

    private static func pixelBytes(of image: NSImage) -> Int {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage.width * cgImage.height * 4
        }
        return max(1, Int(image.size.width * image.size.height * 4))
    }
}

struct CachedRemoteImageView: View {
    let url: URL
    var maxPixelSize: CGFloat = 700
    var contentMode: ContentMode = .fill
    var referer: URL?
    /// 非空时在解码完成前显示转圈与提示；单张大图舞台用，缩略图条不用。
    var loadingHint: String?

    @State private var image: NSImage?
    @State private var didFail = false
    @State private var reloadToken = 0

    init(
        url: URL,
        maxPixelSize: CGFloat = 700,
        contentMode: ContentMode = .fill,
        referer: URL? = nil,
        loadingHint: String? = nil
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        self.referer = referer
        self.loadingHint = loadingHint
        // 预取命中时用内存缓存同步兜底：切换/重建视图首帧即有图，避免空帧闪动。
        let key = RemoteImageLoader.cacheKey(url: url, maxPixelSize: maxPixelSize)
        _image = State(initialValue: RemoteImageMemoryCache.shared.image(for: key))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder
            }
        }
        .animation(.easeOut(duration: 0.18), value: isLoaded)
        .task(id: taskKey) {
            await load()
        }
    }

    /// 舞台背后是环境光模糊图，占位一律透明，避免加载/重载期间铺灰底盖掉背景。
    private var placeholder: some View {
        Color.clear
            .overlay { placeholderContent }
    }

    @ViewBuilder
    private var placeholderContent: some View {
        if didFail {
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("无法加载")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button("重试") {
                    reloadToken += 1
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if let loadingHint {
            VStack(spacing: 8) {
                ProgressView()

                Text(loadingHint)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var isLoaded: Bool {
        image != nil
    }

    /// 尺寸随窗口变化、以及重试，都要能重新触发加载。
    private var taskKey: String {
        "\(RemoteImageLoader.cacheKey(url: url, maxPixelSize: maxPixelSize))#\(reloadToken)"
    }

    private func load() async {
        didFail = false
        // 不清空旧图：窗口缩放触发重载时保留当前图，避免闪回占位造成灰底/闪动。
        if let loaded = await RemoteImageLoader.load(url: url, maxPixelSize: maxPixelSize, referer: referer) {
            image = loaded
        } else {
            didFail = true
        }
    }
}
