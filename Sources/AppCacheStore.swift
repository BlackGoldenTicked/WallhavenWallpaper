import AppKit
import CryptoKit
import Foundation

enum AppCacheSettings {
    static let cacheEnabledKey = "cacheEnabled"
    static let cacheMaxSizeMBKey = "cacheMaxSizeMB"

    static var isEnabled: Bool {
        if UserDefaults.standard.object(forKey: cacheEnabledKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: cacheEnabledKey)
    }

    static var maxSizeBytes: Int {
        let value = UserDefaults.standard.integer(forKey: cacheMaxSizeMBKey)
        let megabytes = value == 0 ? 1024 : value
        return megabytes * 1024 * 1024
    }

    static var rootDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WallhavenWallpaper", isDirectory: true)
    }
}

struct CacheUsage: Sendable {
    let searchBytes: Int
    let thumbnailBytes: Int

    var totalBytes: Int {
        searchBytes + thumbnailBytes
    }
}

actor AppCacheStore {
    static let shared = AppCacheStore()

    private let fileManager = FileManager.default
    private let rootDirectory = AppCacheSettings.rootDirectory

    private var searchDirectory: URL {
        rootDirectory.appendingPathComponent("Search", isDirectory: true)
    }

    private var thumbnailDirectory: URL {
        rootDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    func cachedSearchData(for url: URL, ttl: TimeInterval) throws -> Data? {
        guard AppCacheSettings.isEnabled else { return nil }
        let fileURL = searchDirectory.appendingPathComponent(cacheKey(for: url.absoluteString)).appendingPathExtension("json")
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
        guard let modifiedAt = values.contentModificationDate,
              Date().timeIntervalSince(modifiedAt) <= ttl else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    func storeSearchData(_ data: Data, for url: URL) throws {
        guard AppCacheSettings.isEnabled else { return }
        try fileManager.createDirectory(at: searchDirectory, withIntermediateDirectories: true)
        let fileURL = searchDirectory.appendingPathComponent(cacheKey(for: url.absoluteString)).appendingPathExtension("json")
        try data.write(to: fileURL, options: .atomic)
        try trimIfNeeded()
    }

    func cachedThumbnailData(for url: URL) throws -> Data? {
        guard AppCacheSettings.isEnabled else { return nil }
        let fileURL = thumbnailFileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return try Data(contentsOf: fileURL)
    }

    /// 已缓存原图文件的 URL（未命中或缓存关闭返回 nil）：供下载复用，直接本地拷贝免二次下载。
    func cachedThumbnailFileURL(for url: URL) -> URL? {
        guard AppCacheSettings.isEnabled else { return nil }
        let fileURL = thumbnailFileURL(for: url)
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func storeThumbnailData(_ data: Data, for url: URL) throws {
        guard AppCacheSettings.isEnabled else { return }
        try fileManager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        try data.write(to: thumbnailFileURL(for: url), options: .atomic)
        try trimIfNeeded()
    }

    func usage() -> CacheUsage {
        CacheUsage(
            searchBytes: directorySize(searchDirectory),
            thumbnailBytes: directorySize(thumbnailDirectory)
        )
    }

    func clearSearchCache() throws {
        try removeDirectory(searchDirectory)
    }

    func clearThumbnailCache() throws {
        try removeDirectory(thumbnailDirectory)
        RemoteImageMemoryCache.shared.removeAll()
    }

    func clearAll() throws {
        try removeDirectory(rootDirectory)
        RemoteImageMemoryCache.shared.removeAll()
        LocalImageMemoryCache.shared.removeAll()
    }

    private func thumbnailFileURL(for url: URL) -> URL {
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return thumbnailDirectory.appendingPathComponent(cacheKey(for: url.absoluteString)).appendingPathExtension(ext)
    }

    private func cacheKey(for value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func trimIfNeeded() throws {
        let maxSize = AppCacheSettings.maxSizeBytes
        guard maxSize > 0 else { return }

        var entries = cachedFiles(in: rootDirectory)
        var totalSize = entries.reduce(0) { $0 + $1.size }
        guard totalSize > maxSize else { return }

        entries.sort { $0.modifiedAt < $1.modifiedAt }
        for entry in entries {
            try? fileManager.removeItem(at: entry.url)
            totalSize -= entry.size
            if totalSize <= maxSize { break }
        }
    }

    private func cachedFiles(in directory: URL) -> [(url: URL, size: Int, modifiedAt: Date)] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private func directorySize(_ directory: URL) -> Int {
        cachedFiles(in: directory).reduce(0) { $0 + $1.size }
    }

    private func removeDirectory(_ directory: URL) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}

final class RemoteImageMemoryCache: @unchecked Sendable {
    static let shared = RemoteImageMemoryCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 180
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: NSImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

final class LocalImageMemoryCache: @unchecked Sendable {
    static let shared = LocalImageMemoryCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 220
        cache.totalCostLimit = 160 * 1024 * 1024
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func set(_ image: NSImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
