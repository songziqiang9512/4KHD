import Foundation

enum GallerySection: String, CaseIterable, Identifiable {
    case latest
    case popular
    case cosplay
    case album
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "最新"
        case .popular: "推荐"
        case .cosplay: "Cosplay"
        case .album: "写真"
        case .favorites: "收藏"
        }
    }

    var siteURL: URL? {
        switch self {
        case .latest:
            URL(string: "https://www.4khd.com/")!
        case .popular:
            URL(string: "https://www.4khd.com/pages/popular")!
        case .cosplay:
            URL(string: "https://www.4khd.com/pages/cosplay")!
        case .album:
            URL(string: "https://www.4khd.com/pages/album")!
        case .favorites:
            nil
        }
    }

    var isNetworkBacked: Bool {
        siteURL != nil
    }
}

enum ContentKind: String, Codable {
    case gallery
    case recommended
    case advertisement
}

struct GalleryItem: Identifiable {
    let id: String
    let section: GallerySection
    let kind: ContentKind
    let title: String
    let rawTitle: String
    let subtitle: String
    let detailURL: URL
    let coverURL: URL?
    let imageCount: Int
    let pageCount: Int
    let pageURLs: [URL]
    let sampleImageURLs: [URL]
}

struct FavoriteGalleryItem: Codable, Identifiable, Hashable {
    let id: String
    let sectionRawValue: String
    let title: String
    let rawTitle: String
    let subtitle: String
    let detailURL: String
    let coverURL: String?
    let imageCount: Int
    let pageCount: Int
}

struct ImageSlot: Identifiable {
    let id: String
    let displayIndex: Int
    let pageURL: URL
    let pageImageIndex: Int
    let knownURL: URL?
}

struct ResolvedImagePage {
    let pageURL: URL
    let imageURLs: [URL]
    let pageURLs: [URL]
}

enum GalleryImageURLNormalizer {
    nonisolated static func normalized(_ url: URL) -> URL {
        guard url.host?.lowercased() == "i0.wp.com" else { return url }
        let path = url.path
        let prefix = "/pic.4khd.com/"
        guard path.hasPrefix(prefix) else { return url }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "img.4khd.com"
        components.path = "/" + path.dropFirst(prefix.count)
        components.query = url.query
        return components.url ?? url
    }
}
