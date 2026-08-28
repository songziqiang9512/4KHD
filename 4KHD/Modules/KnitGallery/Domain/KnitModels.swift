import Foundation

/// xx.knit.bid 的所有入口都是互斥路径，不支持“图片类型 × 排行/专题”组合查询。
/// `rawValue` 直接作为工作区路由 itemID，使工具栏筛选可恢复、可深链。
nonisolated enum KnitBrowseFilter: String, CaseIterable, Identifiable, Sendable {
    case all

    case sexy = "type-1"
    case pure = "type-2"
    case stockings = "type-3"
    case legs = "type-4"
    case bust = "type-5"
    case cosplay = "type-6"
    case uniform = "type-7"
    case internet = "type-8"
    case uncensored = "type-9"
    case ai = "type-10"

    case newest = "sort-new"
    case popular = "sort-hot"
    case daily = "ranking-daily"
    case threeDays = "ranking-3days"
    case weekly = "ranking-weekly"
    case monthly = "ranking-monthly"

    case behindTheScenes = "bits-of-news"

    case topicLingerieBeauty = "topic-lingerie-beauty"
    case topicBeautifulHips = "topic-beautiful-hips"
    case topicProvocativeBeauty = "topic-provocative-beauty"
    case topicSexyLingerie = "topic-sexy-lingerie"
    case topicWhiteSilkStockings = "topic-white-silk-stockings"
    case topicBlackSilkStockings = "topic-black-silk-stockings"
    case topicStockingAllure = "topic-stocking-allure"
    case topicBlackSilkAllure = "topic-black-silk-allure"
    case topicLongLegBeauty = "topic-long-leg-beauty"
    case topicQipaoBeauty = "topic-qipao-beauty"
    case topicBeautifulBust = "topic-beautiful-bust"
    case topicBustyBeauty = "topic-busty-beauty"
    case topicMeiruBeauty = "topic-meiru-beauty"
    case topicJKHighlights = "topic-jk-highlights"
    case topicWenmeiCosplay = "topic-wenmei-bujiangdaoli-cosplay"
    case topicCosplayWhiteSilk = "topic-cosplay-white-silk"
    case topicCosplayBlackSilk = "topic-cosplay-black-silk"
    case topicBlackSilkUniform = "topic-black-silk-uniform"
    case topicUniformFantasy = "topic-uniform-fantasy"
    case topicBaihuFulijiVideo = "topic-baihu-fuliji-video"
    case topicExplicitBeauty = "topic-explicit-beauty"
    case topicAIGeneratedCollections = "topic-ai-generated-collections"
    case topicAIPorn = "topic-ai-porn"
    case topicAncientStyleAIPorn = "topic-ancient-style-ai-porn"
    case topicAzurLaneAIGirls = "topic-azur-lane-ai-girls"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "最近更新"
        case .sexy: "性感美女"
        case .pure: "清纯美女"
        case .stockings: "丝袜美女"
        case .legs: "美腿美女"
        case .bust: "美胸美女"
        case .cosplay: "Cosplay"
        case .uniform: "制服诱惑"
        case .internet: "网络美女"
        case .uncensored: "大尺度美女"
        case .ai: "AI 美女"
        case .newest: "最新发布"
        case .popular: "最受欢迎"
        case .daily: "今日热门"
        case .threeDays: "3 天热门"
        case .weekly: "本周热门"
        case .monthly: "本月热门"
        case .behindTheScenes: "影片花絮"
        case .topicLingerieBeauty: "内衣美女精选"
        case .topicBeautifulHips: "美臀美女精选"
        case .topicProvocativeBeauty: "风骚美女精选"
        case .topicSexyLingerie: "情趣内衣精选"
        case .topicWhiteSilkStockings: "白丝美女精选"
        case .topicBlackSilkStockings: "黑丝美女精选"
        case .topicStockingAllure: "丝袜诱惑精选"
        case .topicBlackSilkAllure: "黑丝诱惑精选"
        case .topicLongLegBeauty: "美腿美女精选"
        case .topicQipaoBeauty: "旗袍美女精选"
        case .topicBeautifulBust: "美胸美女精选"
        case .topicBustyBeauty: "巨乳美女精选"
        case .topicMeiruBeauty: "美乳美女精选"
        case .topicJKHighlights: "JK 精选"
        case .topicWenmeiCosplay: "雯妹不讲道理 Cosplay 写真合集"
        case .topicCosplayWhiteSilk: "白丝 Cosplay 精选"
        case .topicCosplayBlackSilk: "黑丝 Cosplay 精选"
        case .topicBlackSilkUniform: "黑丝制服精选"
        case .topicUniformFantasy: "制服诱惑精选"
        case .topicBaihuFulijiVideo: "白虎福利姬私房视频"
        case .topicExplicitBeauty: "大尺度美女精选"
        case .topicAIGeneratedCollections: "AI 生成图集专题"
        case .topicAIPorn: "AI Porn 图库"
        case .topicAncientStyleAIPorn: "古风 AI 成人图集"
        case .topicAzurLaneAIGirls: "碧蓝航线 AI 美图"
        }
    }

    var basePath: String {
        switch self {
        case .all: "/"
        case .sexy: "/type/1/"
        case .pure: "/type/2/"
        case .stockings: "/type/3/"
        case .legs: "/type/4/"
        case .bust: "/type/5/"
        case .cosplay: "/type/6/"
        case .uniform: "/type/7/"
        case .internet: "/type/8/"
        case .uncensored: "/type/9/"
        case .ai: "/type/10/"
        case .newest: "/sort/new/"
        case .popular: "/sort/hot/"
        case .daily: "/rankings/daily/"
        case .threeDays: "/rankings/3days/"
        case .weekly: "/rankings/weekly/"
        case .monthly: "/rankings/monthly/"
        case .behindTheScenes: "/bits-of-news/"
        case .topicLingerieBeauty: "/topic/lingerie-beauty/"
        case .topicBeautifulHips: "/topic/beautiful-hips/"
        case .topicProvocativeBeauty: "/topic/provocative-beauty/"
        case .topicSexyLingerie: "/topic/sexy-lingerie/"
        case .topicWhiteSilkStockings: "/topic/white-silk-stockings/"
        case .topicBlackSilkStockings: "/topic/black-silk-stockings/"
        case .topicStockingAllure: "/topic/stocking-allure/"
        case .topicBlackSilkAllure: "/topic/black-silk-allure/"
        case .topicLongLegBeauty: "/topic/long-leg-beauty/"
        case .topicQipaoBeauty: "/topic/qipao-beauty/"
        case .topicBeautifulBust: "/topic/beautiful-bust/"
        case .topicBustyBeauty: "/topic/busty-beauty/"
        case .topicMeiruBeauty: "/topic/meiru-beauty/"
        case .topicJKHighlights: "/topic/jk-highlights/"
        case .topicWenmeiCosplay: "/topic/wenmei-bujiangdaoli-cosplay/"
        case .topicCosplayWhiteSilk: "/topic/cosplay-white-silk/"
        case .topicCosplayBlackSilk: "/topic/cosplay-black-silk/"
        case .topicBlackSilkUniform: "/topic/black-silk-uniform/"
        case .topicUniformFantasy: "/topic/uniform-fantasy/"
        case .topicBaihuFulijiVideo: "/topic/baihu-fuliji-video/"
        case .topicExplicitBeauty: "/topic/explicit-beauty/"
        case .topicAIGeneratedCollections: "/topic/ai-generated-collections/"
        case .topicAIPorn: "/topic/ai-porn/"
        case .topicAncientStyleAIPorn: "/topic/ancient-style-ai-porn/"
        case .topicAzurLaneAIGirls: "/topic/azur-lane-ai-girls/"
        }
    }

    var sidebarSection: KnitSidebarSection {
        switch self {
        case .all:
            .recentUpdates
        case .sexy, .pure, .stockings, .legs, .bust, .cosplay, .uniform, .internet, .uncensored, .ai,
             .topicLingerieBeauty, .topicBeautifulHips, .topicProvocativeBeauty, .topicSexyLingerie,
             .topicWhiteSilkStockings, .topicBlackSilkStockings, .topicStockingAllure, .topicBlackSilkAllure,
             .topicLongLegBeauty, .topicQipaoBeauty, .topicBeautifulBust, .topicBustyBeauty, .topicMeiruBeauty,
             .topicJKHighlights, .topicWenmeiCosplay, .topicCosplayWhiteSilk, .topicCosplayBlackSilk,
             .topicBlackSilkUniform, .topicUniformFantasy, .topicBaihuFulijiVideo, .topicExplicitBeauty,
             .topicAIGeneratedCollections, .topicAIPorn, .topicAncientStyleAIPorn, .topicAzurLaneAIGirls:
            .girls
        case .newest, .popular, .daily, .threeDays, .weekly, .monthly:
            .rankings
        case .behindTheScenes:
            .video
        }
    }

    var parentGirlType: KnitBrowseFilter? {
        switch self {
        case .sexy, .topicLingerieBeauty, .topicBeautifulHips, .topicProvocativeBeauty, .topicSexyLingerie:
            .sexy
        case .pure:
            .pure
        case .stockings, .topicWhiteSilkStockings, .topicBlackSilkStockings, .topicStockingAllure, .topicBlackSilkAllure:
            .stockings
        case .legs, .topicLongLegBeauty, .topicQipaoBeauty:
            .legs
        case .bust, .topicBeautifulBust, .topicBustyBeauty, .topicMeiruBeauty:
            .bust
        case .cosplay, .topicJKHighlights, .topicWenmeiCosplay, .topicCosplayWhiteSilk, .topicCosplayBlackSilk:
            .cosplay
        case .uniform, .topicBlackSilkUniform, .topicUniformFantasy:
            .uniform
        case .internet:
            .internet
        case .uncensored, .topicBaihuFulijiVideo, .topicExplicitBeauty:
            .uncensored
        case .ai, .topicAIGeneratedCollections, .topicAIPorn, .topicAncientStyleAIPorn, .topicAzurLaneAIGirls:
            .ai
        default:
            nil
        }
    }

    static let girlTypes: [KnitBrowseFilter] = [
        .sexy, .pure, .stockings, .legs, .bust, .cosplay, .uniform, .internet, .uncensored, .ai
    ]

    static let rankingFilters: [KnitBrowseFilter] = [
        .newest, .popular, .daily, .threeDays, .weekly, .monthly
    ]

    static func relatedTopics(for girlType: KnitBrowseFilter) -> [KnitBrowseFilter] {
        switch girlType {
        case .sexy:
            [.topicLingerieBeauty, .topicBeautifulHips, .topicProvocativeBeauty, .topicSexyLingerie]
        case .stockings:
            [.topicWhiteSilkStockings, .topicBlackSilkStockings, .topicStockingAllure, .topicBlackSilkAllure]
        case .legs:
            [.topicLongLegBeauty, .topicQipaoBeauty]
        case .bust:
            [.topicBeautifulBust, .topicBustyBeauty, .topicMeiruBeauty]
        case .cosplay:
            [.topicJKHighlights, .topicWenmeiCosplay, .topicCosplayWhiteSilk, .topicCosplayBlackSilk]
        case .uniform:
            [.topicBlackSilkUniform, .topicUniformFantasy]
        case .uncensored:
            [.topicBaihuFulijiVideo, .topicExplicitBeauty]
        case .ai:
            [.topicAIGeneratedCollections, .topicAIPorn, .topicAncientStyleAIPorn, .topicAzurLaneAIGirls]
        default:
            []
        }
    }

    static func filter(forRouteItemID itemID: String) -> KnitBrowseFilter? {
        if let filter = KnitBrowseFilter(rawValue: itemID) { return filter }
        return switch itemID {
        case "latest": .all
        case "popular": .popular
        case "video": .behindTheScenes
        default: nil
        }
    }
}

nonisolated enum KnitSidebarSection: String, CaseIterable, Identifiable, Sendable {
    case recentUpdates
    case girls
    case rankings
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentUpdates: "最近更新"
        case .girls: "妹子图"
        case .rankings: "排行榜"
        case .video: "影片花絮"
        }
    }

    var defaultFilter: KnitBrowseFilter {
        switch self {
        case .recentUpdates: .all
        case .girls: .stockings
        case .rankings: .popular
        case .video: .behindTheScenes
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .recentUpdates: "clock.arrow.circlepath"
        case .girls: "photo.on.rectangle.angled"
        case .rankings: "chart.bar.fill"
        case .video: "play.rectangle"
        }
    }

    func matches(_ filter: KnitBrowseFilter) -> Bool {
        filter.sidebarSection == self
    }
}

nonisolated struct KnitGalleryItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let rawTitle: String
    let category: String
    let publishedDate: String
    let viewCount: Int?
    let detailURL: URL
    let coverURL: URL?
    let coverAspectRatio: Double
    let reportedPhotoCount: Int
    let reportedGIFCount: Int
    let reportedVideoCount: Int

    var hasVideo: Bool { reportedVideoCount > 0 }

    /// 标题里的 P 包含 G 时，减去 G 更接近站点实际图片分页数量。
    var estimatedImageCount: Int {
        max(reportedPhotoCount - reportedGIFCount, 0)
    }

    var metadataText: String {
        var parts: [String] = []
        if reportedPhotoCount > 0 { parts.append("\(reportedPhotoCount)P") }
        if reportedGIFCount > 0 { parts.append("\(reportedGIFCount)G") }
        if reportedVideoCount > 0 { parts.append("\(reportedVideoCount)V") }
        if let viewCount { parts.append("\(viewCount) 浏览") }
        return parts.joined(separator: " · ")
    }
}

nonisolated enum KnitListContext: Hashable, Sendable {
    case filter(KnitBrowseFilter)
    case search(String)

    func pageURL(page: Int, includesAJAX: Bool = true) -> URL? {
        let safePage = max(page, 1)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "xx.knit.bid"
        switch self {
        case .filter(let filter):
            let basePath = filter.basePath
            components.path = safePage == 1 ? basePath : "\(basePath)page/\(safePage)/"
            components.queryItems = includesAJAX ? [URLQueryItem(name: "ajax", value: "1")] : nil
        case .search(let query):
            components.path = safePage == 1 ? "/search/" : "/search/page/\(safePage)/"
            var queryItems = [URLQueryItem(name: "s", value: query)]
            if includesAJAX { queryItems.append(URLQueryItem(name: "ajax", value: "1")) }
            components.queryItems = queryItems
        }
        return components.url
    }
}

nonisolated struct KnitListPage: Sendable {
    let items: [KnitGalleryItem]
    let currentPage: Int
    let totalPages: Int
    let nextPageURL: URL?
}

nonisolated struct KnitImageSlot: Identifiable, Hashable, Sendable {
    let id: String
    let displayIndex: Int
    let pageURL: URL
    let knownURL: URL
}

nonisolated struct KnitDetailMetadata: Sendable, Equatable {
    let description: String
    let tags: [String]
    let totalImages: Int
    let totalPages: Int
}

nonisolated struct KnitResolvedDetailPage: Sendable {
    let pageURL: URL
    let imageURLs: [URL]
    let pageURLs: [URL]
    let videoURL: URL?
    let metadata: KnitDetailMetadata?
    let recommendations: [OnlineGalleryRecommendation]

    init(
        pageURL: URL,
        imageURLs: [URL],
        pageURLs: [URL],
        videoURL: URL?,
        metadata: KnitDetailMetadata?,
        recommendations: [OnlineGalleryRecommendation] = []
    ) {
        self.pageURL = pageURL
        self.imageURLs = imageURLs
        self.pageURLs = pageURLs
        self.videoURL = videoURL
        self.metadata = metadata
        self.recommendations = recommendations
    }
}
