import AppKit
import ImageIO

enum LocalImageLoader {
    static func load(url: URL, maxPixelSize: CGFloat = 1200) async -> NSImage? {
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
        if let cachedImage = LocalImageMemoryCache.shared.image(for: key) {
            return cachedImage
        }

        let image = await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
                return NSImage(contentsOf: url)
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value

        if let image {
            LocalImageMemoryCache.shared.set(image, for: key, cost: localFileSize(url))
        }
        return image
    }

    private static func cacheKey(for url: URL, maxPixelSize: CGFloat) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values?.fileSize ?? 0
        return "\(url.path)|\(Int(maxPixelSize))|\(modifiedAt)|\(fileSize)"
    }

    private static func localFileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1
    }
}
