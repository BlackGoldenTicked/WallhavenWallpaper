import AppKit
import Foundation

struct WallhavenImage: Decodable, Identifiable {
    let id: String
    let url: URL
    let path: URL
    let purity: String
    let category: String
    let resolution: String
    let fileSize: Int
    let thumbs: WallhavenThumbs

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case path
        case purity
        case category
        case resolution
        case fileSize = "file_size"
        case thumbs
    }
}

struct WallhavenThumbs: Decodable {
    let large: URL
    let original: URL
    let small: URL
}

struct WallhavenMeta: Decodable {
    let currentPage: Int
    let lastPage: Int
    let perPage: Int
    let total: Int
    let seed: String?

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
        case perPage = "per_page"
        case total
        case seed
    }
}

struct WallhavenResponse: Decodable {
    let data: [WallhavenImage]
    let meta: WallhavenMeta
}

struct WallhavenSearchResult {
    let images: [WallhavenImage]
    let meta: WallhavenMeta
    let isFromCache: Bool
}

struct WallhavenSearchOptions {
    var listing: WallhavenListing
    var query: String
    var categories: String
    var purity: PurityFilter
    var sorting: WallhavenSorting
    var orderDescending: Bool
    var topRange: TopRange
    var resolutionMode: ResolutionMode
    var resolution: String
    var ratios: String
    var color: String
    var apiKey: String
    var page: Int
    var seed: String?
}

struct DownloadedWallpaper {
    let image: WallhavenImage
    let localURL: URL
}

enum WallpaperError: LocalizedError {
    case missingImageData
    case badHTTPStatus(Int)
    case wallpaperScreenUnavailable

    var errorDescription: String? {
        switch self {
        case .missingImageData: "图片数据为空"
        case .badHTTPStatus(let status): "请求失败：HTTP \(status)"
        case .wallpaperScreenUnavailable: "找不到当前屏幕"
        }
    }
}

final class WallhavenService: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ options: WallhavenSearchOptions) async throws -> WallhavenSearchResult {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var queryItems = [
            URLQueryItem(name: "categories", value: options.categories),
            URLQueryItem(name: "purity", value: options.purity.wallhavenValue),
            URLQueryItem(name: "sorting", value: options.sorting.rawValue),
            URLQueryItem(name: "order", value: options.orderDescending ? "desc" : "asc"),
            URLQueryItem(name: "page", value: "\(options.page)")
        ]

        let trimmedQuery = options.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: trimmedQuery))
        }

        if options.sorting == .toplist {
            queryItems.append(URLQueryItem(name: "topRange", value: options.topRange.rawValue))
        }

        let trimmedResolution = options.resolution.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedResolution.isEmpty {
            queryItems.append(URLQueryItem(
                name: options.resolutionMode == .atLeast ? "atleast" : "resolutions",
                value: trimmedResolution
            ))
        }

        let trimmedRatios = options.ratios.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRatios.isEmpty {
            queryItems.append(URLQueryItem(name: "ratios", value: trimmedRatios))
        }

        let trimmedColor = options.color.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedColor.isEmpty {
            queryItems.append(URLQueryItem(name: "colors", value: trimmedColor))
        }

        if options.sorting == .random, let seed = options.seed, !seed.isEmpty {
            queryItems.append(URLQueryItem(name: "seed", value: seed))
        }

        let trimmedAPIKey = options.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAPIKey.isEmpty {
            queryItems.append(URLQueryItem(name: "apikey", value: trimmedAPIKey))
        }

        components.queryItems = queryItems
        let url = components.url!
        let ttl = searchCacheTTL(for: options)
        let shouldUseSearchCache = !(options.sorting == .random && (options.seed ?? "").isEmpty)

        if shouldUseSearchCache,
           let cachedData = try await AppCacheStore.shared.cachedSearchData(for: url, ttl: ttl) {
            let response = try JSONDecoder().decode(WallhavenResponse.self, from: cachedData)
            return WallhavenSearchResult(images: response.data, meta: response.meta, isFromCache: true)
        }

        let (data, _) = try await data(from: url, referer: URL(string: "https://wallhaven.cc/"))
        if shouldUseSearchCache {
            try await AppCacheStore.shared.storeSearchData(data, for: url)
        }
        let response = try JSONDecoder().decode(WallhavenResponse.self, from: data)
        return WallhavenSearchResult(images: response.data, meta: response.meta, isFromCache: false)
    }

    func fetchToplist(
        purity: PurityFilter,
        apiKey: String,
        page: Int = 1
    ) async throws -> [WallhavenImage] {
        try await search(WallhavenSearchOptions(
            listing: .toplist,
            query: "",
            categories: "111",
            purity: purity,
            sorting: .toplist,
            orderDescending: true,
            topRange: .oneMonth,
            resolutionMode: .atLeast,
            resolution: "1920x1080",
            ratios: "",
            color: "",
            apiKey: apiKey,
            page: page,
            seed: nil
        )).images
    }

    func download(
        _ image: WallhavenImage,
        grouping: DownloadGrouping,
        rootDirectory: URL
    ) async throws -> DownloadedWallpaper {
        let directory = targetDirectory(rootDirectory: rootDirectory, grouping: grouping, date: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileName = "wallhaven-\(image.id)." + (image.path.pathExtension.isEmpty ? "jpg" : image.path.pathExtension)
        let localURL = directory.appendingPathComponent(fileName)

        // 浏览时原图已进磁盘缓存则直接本地拷贝，免二次下载；未命中才走网络。
        if let cachedFileURL = await AppCacheStore.shared.cachedThumbnailFileURL(for: image.path) {
            _ = try? FileManager.default.removeItem(at: localURL)
            try FileManager.default.copyItem(at: cachedFileURL, to: localURL)
        } else {
            let (data, _) = try await data(from: image.path, referer: image.url)
            guard !data.isEmpty else { throw WallpaperError.missingImageData }
            try data.write(to: localURL, options: .atomic)
        }
        return DownloadedWallpaper(image: image, localURL: localURL)
    }

    func setDesktopWallpaper(_ fileURL: URL, onAllScreens: Bool = false) throws {
        let screens = onAllScreens ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        guard !screens.isEmpty else { throw WallpaperError.wallpaperScreenUnavailable }
        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen)
        }
    }

    static var defaultRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures")
            .appendingPathComponent("wallpaper")
            .appendingPathComponent("电脑壁纸")
    }

    private func targetDirectory(rootDirectory: URL, grouping: DownloadGrouping, date: Date) -> URL {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let day = String(format: "%02d", calendar.component(.day, from: date))

        switch grouping {
        case .month:
            return rootDirectory
                .appendingPathComponent("\(year)")
                .appendingPathComponent(month)
        case .day:
            return rootDirectory
                .appendingPathComponent("\(year)")
                .appendingPathComponent(month)
                .appendingPathComponent(day)
        }
    }

    private func searchCacheTTL(for options: WallhavenSearchOptions) -> TimeInterval {
        switch options.listing {
        case .latest, .hot:
            20 * 60
        case .toplist:
            12 * 60 * 60
        case .random:
            60 * 60
        case .search:
            24 * 60 * 60
        }
    }

    private func data(from url: URL, referer: URL?) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) WallhavenWallpaper/1.0", forHTTPHeaderField: "User-Agent")
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
        }

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw WallpaperError.badHTTPStatus(httpResponse.statusCode)
        }
        return (data, response)
    }
}
