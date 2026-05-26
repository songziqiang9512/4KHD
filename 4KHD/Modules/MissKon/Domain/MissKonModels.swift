import Foundation

enum MissKonSection: String, CaseIterable, Identifiable {
    case latest
    case cosplay
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "最新"
        case .cosplay: "Cosplay"
        case .favorites: "收藏"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .latest: "sparkles"
        case .cosplay: "theatermasks"
        case .favorites: "heart"
        }
    }

    var siteURL: URL? {
        switch self {
        case .latest: URL(string: "https://misskon.com/")!
        case .cosplay: URL(string: "https://misskon.com/tag/cosplay/")!
        case .favorites: nil
        }
    }

    var isNetworkBacked: Bool { siteURL != nil }
}

struct MissKonItem: Identifiable {
    let id: String
    let section: MissKonSection
    let title: String
    let detailURL: URL
    let coverURL: URL?
    let coverAspectRatio: Double?
    let imageCount: Int
    let pageCount: Int
    let pageURLs: [URL]
    let tags: [String]
}

struct MissKonImageSlot: Identifiable {
    let id: String
    let displayIndex: Int
    let pageURL: URL
    let pageImageIndex: Int
    let knownURL: URL?
}

struct MissKonResolvedImagePage {
    let pageURL: URL
    let imageURLs: [URL]
    let pageURLs: [URL]
}
