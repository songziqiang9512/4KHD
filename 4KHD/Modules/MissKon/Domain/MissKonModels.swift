import Foundation

enum MissKonSection: String, CaseIterable, Identifiable {
    case latest
    case top30
    case aiGenerated
    case privatePhotoshoot
    case xiuren
    case huayang
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "最新"
        case .top30: "热门"
        case .aiGenerated: "AI 生成"
        case .privatePhotoshoot: "私房摄影"
        case .xiuren: "秀人"
        case .huayang: "花漾"
        case .favorites: "收藏"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .latest: "sparkles"
        case .top30: "flame"
        case .aiGenerated: "cpu"
        case .privatePhotoshoot: "camera.aperture"
        case .xiuren: "person.crop.rectangle"
        case .huayang: "person.crop.rectangle.fill"
        case .favorites: "heart"
        }
    }

    var siteURL: URL? {
        switch self {
        case .latest: URL(string: "https://misskon.com/")!
        case .top30: URL(string: "https://misskon.com/top30/")!
        case .aiGenerated: URL(string: "https://misskon.com/tag/ai-enhanced/")!
        case .privatePhotoshoot: URL(string: "https://misskon.com/tag/private-photoshoot/")!
        case .xiuren: URL(string: "https://misskon.com/tag/xiuren/")!
        case .huayang: URL(string: "https://misskon.com/tag/huayang/")!
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
