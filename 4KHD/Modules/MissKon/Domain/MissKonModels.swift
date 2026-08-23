import Foundation

enum MissKonSection: String, CaseIterable, Identifiable, Codable {
    case latest
    case top30
    case cosplay
    case aiGenerated
    case otherxxx
    case xrUncensored
    case bluecake
    case pureMedia
    case xLevel
    case xiaoyu
    case privatePhotoshoot
    case xiuren
    case huayang

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: "最新"
        case .top30: "热门"
        case .cosplay: "Cosplay"
        case .aiGenerated: "AI 增强"
        case .otherxxx: "OtherXXX"
        case .xrUncensored: "XR Uncensored"
        case .bluecake: "BLUECAKE"
        case .pureMedia: "Pure Media"
        case .xLevel: "X-Level"
        case .xiaoyu: "XiaoYu"
        case .privatePhotoshoot: "私房摄影"
        case .xiuren: "秀人"
        case .huayang: "花漾"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .latest: "sparkles"
        case .top30: "flame"
        case .cosplay: "theatermasks"
        case .aiGenerated: "wand.and.stars"
        // 语义不好定义的标签统一用与 XiaoYu 相同的人像图标。
        case .otherxxx: "person.crop.square"
        case .xrUncensored: "person.crop.square"
        case .bluecake: "birthday.cake"
        case .pureMedia: "person.crop.square"
        case .xLevel: "person.crop.square"
        case .xiaoyu: "person.crop.square"
        case .privatePhotoshoot: "camera.aperture"
        case .xiuren: "person.crop.rectangle"
        case .huayang: "camera.macro"
        }
    }

    var siteURL: URL? {
        switch self {
        case .latest: URL(string: "https://misskon.com/")
        case .top30: URL(string: "https://misskon.com/top30/")
        case .cosplay: URL(string: "https://misskon.com/tag/cosplay/")
        case .aiGenerated: URL(string: "https://misskon.com/tag/ai-enhanced/")
        case .otherxxx: URL(string: "https://misskon.com/tag/otherxxx/")
        case .xrUncensored: URL(string: "https://misskon.com/tag/xr-uncensored/")
        case .bluecake: URL(string: "https://misskon.com/tag/bluecake/")
        case .pureMedia: URL(string: "https://misskon.com/tag/pure-media/")
        case .xLevel: URL(string: "https://misskon.com/tag/x-level/")
        case .xiaoyu: URL(string: "https://misskon.com/tag/xiaoyu/")
        case .privatePhotoshoot: URL(string: "https://misskon.com/tag/private-photoshoot/")
        case .xiuren: URL(string: "https://misskon.com/tag/xiuren/")
        case .huayang: URL(string: "https://misskon.com/tag/huayang/")
        }
    }

    var isNetworkBacked: Bool { siteURL != nil }
}

struct MissKonItem: Identifiable, Codable, Hashable {
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

nonisolated struct MissKonResolvedImagePage: Sendable {
    let pageURL: URL
    let imageURLs: [URL]
    let pageURLs: [URL]
    let mediaFireURL: URL?
    let recommendations: [OnlineGalleryRecommendation]

    init(
        pageURL: URL,
        imageURLs: [URL],
        pageURLs: [URL],
        mediaFireURL: URL?,
        recommendations: [OnlineGalleryRecommendation] = []
    ) {
        self.pageURL = pageURL
        self.imageURLs = imageURLs
        self.pageURLs = pageURLs
        self.mediaFireURL = mediaFireURL
        self.recommendations = recommendations
    }
}
