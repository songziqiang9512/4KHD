import Foundation

enum WallpaperSource: String, Codable {
    case wallhaven
}

struct Wallpaper: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let source: WallpaperSource
    let sourcePageUrl: URL
    let sourceUrl: URL?
    let thumbnailUrl: URL?
    let previewUrl: URL?
    let fullImageUrl: URL?
    let width: Int?
    let height: Int?
    let resolutionText: String
    let fileSize: Int64?
    let fileType: String?
    let colors: [String]
    let tags: [String]
    let createdAt: Date?
    let purity: WallhavenPurity
    let category: String?
    let views: Int?
    let favorites: Int?
    let uploader: String?

    var uploaderProfileURL: URL? {
        uploader.flatMap { URL(string: "https://wallhaven.cc/user/\($0)") }
    }

    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return Double(width) / Double(height)
    }

    var cardCoverUrl: URL? {
        previewUrl ?? thumbnailUrl
    }

    var formattedFileSize: String {
        guard let fileSize else { return "-" }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var detailInfoText: String {
        var parts = [
            resolutionText,
            formattedFileSize,
            fileType?.replacingOccurrences(of: "image/", with: "").uppercased(),
            category.map {
                let title = WallhavenCategory(rawValue: $0)?.title ?? $0
                return "分类：\(title)"
            },
        ].compactMap { $0 }.filter { !$0.isEmpty && $0 != "-" }
        let tagText = tags.prefix(8).joined(separator: ", ")
        if !tagText.isEmpty {
            parts.append(tagText)
        }
        return parts.joined(separator: " · ")
    }

    var fileExtensionForSave: String {
        switch fileType?.lowercased() {
        case "image/png": "png"
        case "image/webp": "webp"
        case "image/jpeg", "image/jpg": "jpg"
        default: fullImageUrl?.pathExtension.nilIfEmpty ?? "jpg"
        }
    }
}

enum WallhavenSection: String, CaseIterable, Identifiable {
    case browse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .browse: "浏览"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .browse: "photo.stack"
        }
    }
}

enum WallhavenCategory: String, CaseIterable, Identifiable, Codable {
    case all
    case general
    case anime
    case people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .general: "常规"
        case .anime: "动漫"
        case .people: "人物"
        }
    }

    var apiValue: String {
        switch self {
        case .all: "111"
        case .general: "100"
        case .anime: "010"
        case .people: "001"
        }
    }
}

nonisolated enum WallhavenPurity: String, CaseIterable, Identifiable, Codable {
    case sfw
    case sketchy
    case nsfw
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sfw: "SFW"
        case .sketchy: "Sketchy"
        case .nsfw: "NSFW"
        case .all: "全部"
        }
    }

    var apiValue: String {
        switch self {
        case .sfw: "100"
        case .sketchy: "010"
        case .nsfw: "001"
        case .all: "111"
        }
    }

    var requiresAPIKey: Bool {
        self == .nsfw || self == .all
    }

    func allows(_ itemPurity: WallhavenPurity) -> Bool {
        switch self {
        case .all:
            true
        case .sfw, .sketchy, .nsfw:
            self == itemPurity
        }
    }

    static func fromAPIValue(_ value: String?) -> WallhavenPurity {
        switch value?.lowercased() {
        case "sketchy": .sketchy
        case "nsfw": .nsfw
        default: .sfw
        }
    }
}

enum WallhavenSorting: String, CaseIterable, Identifiable, Codable {
    case toplist
    case dateAdded = "date_added"
    case random
    case favorites
    case views
    case relevance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toplist: "热门"
        case .dateAdded: "最新"
        case .random: "随机"
        case .favorites: "收藏数"
        case .views: "浏览数"
        case .relevance: "相关"
        }
    }
}

enum WallhavenOrder: String, Codable {
    case desc
    case asc
}

enum WallhavenTopRange: String, CaseIterable, Identifiable, Codable {
    case oneDay = "1d"
    case threeDays = "3d"
    case oneWeek = "1w"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1y"

    var id: String { rawValue }
}

enum WallhavenResolution: String, CaseIterable, Identifiable, Codable {
    case any
    case fullHD = "1920x1080"
    case qhd = "2560x1440"
    case uhd = "3840x2160"

    var id: String { rawValue }
    var title: String { self == .any ? "分辨率" : rawValue }
    var apiValue: String? { self == .any ? nil : rawValue }
}

enum WallhavenRatio: String, CaseIterable, Identifiable, Codable {
    case any
    case sixteenNine = "16x9"
    case sixteenTen = "16x10"
    case twentyOneNine = "21x9"
    case nineSixteen = "9x16"

    var id: String { rawValue }
    var title: String { self == .any ? "比例" : rawValue }
    var apiValue: String? { self == .any ? nil : rawValue }
}

struct WallhavenSearchParameters: Hashable {
    var query: String?
    var category: WallhavenCategory
    var purity: WallhavenPurity
    var sorting: WallhavenSorting
    var order: WallhavenOrder
    var topRange: WallhavenTopRange
    var resolution: WallhavenResolution
    var ratio: WallhavenRatio
    var page: Int
    var seed: String?
}

struct WallhavenPage {
    let wallpapers: [Wallpaper]
    let currentPage: Int
    let lastPage: Int
    let total: Int?
    let seed: String?

    var canLoadMore: Bool {
        currentPage < lastPage
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
