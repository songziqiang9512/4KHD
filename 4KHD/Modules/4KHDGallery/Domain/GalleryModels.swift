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

    var sidebarSystemImage: String {
        switch self {
        case .latest: "sparkles"
        case .popular: "flame"
        case .cosplay: "theatermasks"
        case .album: "photo.on.rectangle"
        case .favorites: "bookmark"
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
    let coverAspectRatio: Double?
    let imageCount: Int
    let pageCount: Int
    let pageURLs: [URL]
    let sampleImageURLs: [URL]
}

struct ImageSlot: Identifiable {
    let id: String
    let displayIndex: Int
    let pageURL: URL
    let pageImageIndex: Int
    let knownURL: URL?
}

struct ResolvedImagePage: Sendable {
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

enum GalleryCoverAspectRatio {
    private nonisolated static let resizeRegex = regex(#"(?:\?|&)resize=([0-9]+)(?:%2C|,)([0-9]+)"#)
    private nonisolated static let pathSizeRegex = regex(#"/w([0-9]+)-h([0-9]+)-"#)

    nonisolated static func aspectRatio(from url: URL) -> Double? {
        let absoluteString = url.absoluteString
        return aspectRatio(matching: resizeRegex, in: absoluteString)
            ?? aspectRatio(matching: pathSizeRegex, in: absoluteString)
    }

    private nonisolated static func aspectRatio(matching regex: NSRegularExpression, in value: String) -> Double? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 2,
              let widthRange = Range(match.range(at: 1), in: value),
              let heightRange = Range(match.range(at: 2), in: value),
              let width = Double(value[widthRange]),
              let height = Double(value[heightRange]),
              width > 0,
              height > 0 else {
            return nil
        }
        return width / height
    }

    private nonisolated static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid regex pattern: \(pattern)")
        }
    }
}
