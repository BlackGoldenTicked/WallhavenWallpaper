import Foundation
import SwiftData

enum DownloadGrouping: String, CaseIterable, Identifiable {
    case month
    case day

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month: "按月份"
        case .day: "按日期"
        }
    }
}

enum PurityFilter: String, CaseIterable, Identifiable {
    case sfw
    case sfwSketchy
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sfw: "SFW"
        case .sfwSketchy: "SFW + Sketchy"
        case .all: "含 NSFW"
        }
    }

    var wallhavenValue: String {
        switch self {
        case .sfw: "100"
        case .sfwSketchy: "110"
        case .all: "111"
        }
    }
}

enum WallhavenListing: String, CaseIterable, Identifiable {
    case latest
    case hot
    case toplist
    case random
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "Latest"
        case .hot: "Hot"
        case .toplist: "Toplist"
        case .random: "Random"
        case .search: "社区"
        }
    }

    var defaultSorting: WallhavenSorting {
        switch self {
        case .latest: .dateAdded
        case .hot: .hot
        case .toplist: .toplist
        case .random: .random
        case .search: .relevance
        }
    }
}

enum WallhavenSorting: String, CaseIterable, Identifiable {
    case relevance
    case random
    case dateAdded = "date_added"
    case views
    case favorites
    case toplist
    case hot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: "Relevance"
        case .random: "Random"
        case .dateAdded: "Date Added"
        case .views: "Views"
        case .favorites: "Favorites"
        case .toplist: "Toplist"
        case .hot: "Hot"
        }
    }
}

enum TopRange: String, CaseIterable, Identifiable {
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1y"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay: "1 天"
        case .threeDays: "3 天"
        case .oneWeek: "1 周"
        case .oneMonth: "1 月"
        case .threeMonths: "3 月"
        case .sixMonths: "6 月"
        case .oneYear: "1 年"
        }
    }
}

enum ResolutionMode: String, CaseIterable, Identifiable {
    case atLeast
    case exactly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .atLeast: "至少"
        case .exactly: "精确"
        }
    }
}

enum WallpaperRotationOrder: String, CaseIterable, Identifiable {
    case random
    case sequential
    case reverse
    case newestFirst
    case oldestFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .random: "随机"
        case .sequential: "顺序"
        case .reverse: "倒序"
        case .newestFirst: "最新优先"
        case .oldestFirst: "最旧优先"
        }
    }
}

@Model
final class WallpaperItem {
    @Attribute(.unique) var wallhavenID: String
    var sourceURL: URL
    var imageURL: URL
    var localPath: String
    var purity: String
    var resolution: String
    var fileSize: Int
    var downloadedAt: Date
    var tagsText: String

    init(
        wallhavenID: String,
        sourceURL: URL,
        imageURL: URL,
        localPath: String,
        purity: String,
        resolution: String,
        fileSize: Int,
        downloadedAt: Date = Date(),
        tagsText: String = ""
    ) {
        self.wallhavenID = wallhavenID
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.localPath = localPath
        self.purity = purity
        self.resolution = resolution
        self.fileSize = fileSize
        self.downloadedAt = downloadedAt
        self.tagsText = tagsText
    }

    var fileURL: URL {
        URL(fileURLWithPath: localPath)
    }

    var tags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var groupMonth: String {
        downloadedAt.formatted(.dateTime.year().month(.twoDigits))
    }

    var groupDay: String {
        downloadedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }
}
