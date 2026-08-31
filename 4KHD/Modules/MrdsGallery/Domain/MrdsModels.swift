import Foundation

/// 每日大赛侧边栏入口。rawValue 同时作为工作区路由 itemID。
nonisolated enum MrdsSection: String, CaseIterable, Identifiable {
    case latest
    case mrds
    case ztds
    case rstt
    case xazd
    case blyp
    case fctg
    case mhds
    case lqdp
    case jdsj
    case mxwh
    case smdh
    case dypd
    case mtds
    case ysds
    case czds
    case hjds
    case tgds
    case omjp
    case qwcs
    case aijc

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .latest: "最近更新"
        case .mrds: "每日大赛"
        case .ztds: "主题大赛"
        case .rstt: "热搜吃瓜"
        case .xazd: "校园学生"
        case .blyp: "必撸大赛"
        case .fctg: "反差泄密"
        case .mhds: "网红黑料"
        case .lqdp: "猎奇重口"
        case .jdsj: "AV看片"
        case .mxwh: "明星大赛"
        case .smdh: "动漫之家"
        case .dypd: "影视国漫"
        case .mtds: "cos写真"
        case .ysds: "声控ASMR"
        case .czds: "寸止挑战"
        case .hjds: "混剪PMV"
        case .tgds: "原创投稿"
        case .omjp: "欧美精品"
        case .qwcs: "全网参赛"
        case .aijc: "AI剧场"
        }
    }

    var basePath: String {
        switch self {
        case .latest: "/"
        default: "/category/\(rawValue)/"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .latest: "clock.arrow.circlepath"
        case .blyp, .jdsj, .ysds, .hjds, .omjp: "play.rectangle"
        case .aijc: "sparkles"
        case .mtds: "camera"
        default: "photo.on.rectangle"
        }
    }
}

nonisolated struct MrdsGalleryItem: Identifiable, Hashable {
    let id: String
    let title: String
    let rawTitle: String
    let category: String
    let publishedDate: String
    let detailURL: URL
    let coverURL: URL?
    let coverAspectRatio: Double
    let hasVideo: Bool

    var metadataText: String {
        hasVideo ? "含视频" : ""
    }
}

nonisolated enum MrdsListContext: Hashable {
    case filter(MrdsSection)
    case search(String)

    func pageURL(page: Int) -> URL? {
        let safePage = max(page, 1)
        let path: String
        switch self {
        case let .filter(section):
            if section == .latest {
                path = safePage == 1 ? "/" : "/page/\(safePage)/"
            } else {
                path = safePage == 1
                    ? section.basePath
                    : "/category/\(section.rawValue)/\(safePage)/"
            }
        case let .search(query):
            let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.searchPathAllowed) ?? query
            path = safePage == 1 ? "/search/\(encoded)/" : "/search/\(encoded)/\(safePage)/"
        }
        return URL(string: "https://www.mrds66.com" + path)
    }

    /// Matches the site search form's `encodeURIComponent` so `/`, `+` and
    /// reserved query characters cannot split the Typecho search path.
    private static let searchPathAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return allowed
    }()
}

nonisolated struct MrdsListPage {
    let items: [MrdsGalleryItem]
    let currentPage: Int
    let totalPages: Int
    let nextPageURL: URL?
}

nonisolated struct MrdsImageSlot: Identifiable, Hashable {
    let id: String
    let displayIndex: Int
    let pageURL: URL
    let knownURL: URL
}

nonisolated struct MrdsDetailMetadata: Equatable {
    let description: String
    let tags: [String]
    let totalImages: Int
    let totalPages: Int
}

nonisolated struct MrdsResolvedDetailPage {
    let pageURL: URL
    let imageURLs: [URL]
    let pageURLs: [URL]
    let videoURL: URL?
    let metadata: MrdsDetailMetadata?
    let recommendations: [OnlineGalleryRecommendation]
}
