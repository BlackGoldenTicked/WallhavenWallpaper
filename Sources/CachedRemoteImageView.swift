import AppKit
import ImageIO
import SwiftUI

struct CachedRemoteImageView: View {
    let url: URL
    var maxPixelSize: CGFloat = 900

    @State private var image: NSImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        if didFail {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .task(id: url.absoluteString) {
            await load()
        }
    }

    private func load() async {
        didFail = false
        image = nil
        let key = url.absoluteString

        if let cachedImage = RemoteImageMemoryCache.shared.image(for: key) {
            image = cachedImage
            return
        }

        do {
            let data: Data
            if let cachedData = try await AppCacheStore.shared.cachedThumbnailData(for: url) {
                data = cachedData
            } else {
                data = try await fetchData()
                try await AppCacheStore.shared.storeThumbnailData(data, for: url)
            }

            guard let decodedImage = await decodeImage(data) else {
                didFail = true
                return
            }
            RemoteImageMemoryCache.shared.set(decodedImage, for: key, cost: max(data.count, 1))
            image = decodedImage
        } catch {
            didFail = true
        }
    }

    private func fetchData() async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) WallhavenWallpaper/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw WallpaperError.badHTTPStatus(httpResponse.statusCode)
        }
        return data
    }

    private func decodeImage(_ data: Data) async -> NSImage? {
        let maxPixelSize = maxPixelSize
        return await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
                return NSImage(data: data)
            }

            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
                return NSImage(data: data)
            }
            return NSImage(cgImage: cgImage, size: .zero)
        }.value
    }
}
