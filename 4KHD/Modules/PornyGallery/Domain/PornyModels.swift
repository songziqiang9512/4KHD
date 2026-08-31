import Foundation

/// 91PORNY 侧边栏入口。rawValue 同时是原站分类 slug 和工作区路由 itemID。
nonisolated enum PornySection: String, CaseIterable, Identifiable {
    case latest
    case hd
    case recentFavorite = "recent-favorite"
    case hotList = "hot-list"
    case recentRating = "recent-rating"
    case nonpaid
    case ori
    case longList = "long-list"
    case longerList = "longer-list"
    case monthDiscuss = "month-discuss"
    case topFavorite = "top-favorite"
    case mostFavorite = "most-favorite"
    case topList = "top-list"
    case topLast = "top-last"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .latest: "最近更新"
        case .hd: "高清视频"
        case .recentFavorite: "最近加精"
        case .hotList: "当前最热"
        case .recentRating: "最近得分"
        case .nonpaid: "非付费"
        case .ori: "91原创"
        case .longList: "10分钟以上"
        case .longerList: "20分钟以上"
        case .monthDiscuss: "本月讨论"
        case .topFavorite: "本月收藏"
        case .mostFavorite: "收藏最多"
        case .topList: "本月最热"
        case .topLast: "上月最热"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .latest: "clock.arrow.circlepath"
        case .hd: "tv"
        case .recentFavorite, .topFavorite, .mostFavorite: "heart"
        case .hotList, .topList, .topLast: "flame"
        case .recentRating: "star"
        case .nonpaid: "checkmark.seal"
        case .ori: "person.crop.square"
        case .longList, .longerList: "timer"
        case .monthDiscuss: "text.bubble"
        }
    }

    func listURL(searchQuery: String?) -> URL? {
        if let searchQuery {
            var components = URLComponents(string: "https://91porny.com/search")
            components?.queryItems = [URLQueryItem(name: "keywords", value: searchQuery)]
            return components?.url
        }
        return URL(string: "https://91porny.com/video/category/\(rawValue)")
    }
}

enum PornyGalleryFactory {
    @MainActor
    static func makeStore(favorites: FavoritesStore) -> OnlineVideoGalleryStore {
        OnlineVideoGalleryStore(
            policySource: .porny,
            sourceTitle: "91PORNY",
            defaultFilter: PornySection.latest.rawValue,
            favorites: favorites,
            listURL: { filter, query in
                PornySection(rawValue: filter)?.listURL(searchQuery: query)
            },
            filterTitle: { PornySection(rawValue: $0)?.title ?? "91PORNY" },
            listResolver: PornyListResolver.resolve,
            detailResolver: PornyDetailResolver.resolve,
            makeFavoriteRecord: PornyFavoritesBridge.record(from:)
        )
    }
}

enum PornyFavoritesBridge {
    nonisolated static func record(from item: OnlineVideoItem) -> FavoriteRecord {
        FavoriteRecord(
            id: "porny:\(item.id)",
            sourceID: "porny",
            title: item.title,
            rawTitle: item.title,
            subtitle: [item.subtitle, item.durationText].filter { !$0.isEmpty }.joined(separator: " · "),
            detailURL: item.detailURL.absoluteString,
            coverURL: item.coverURL?.absoluteString,
            imageCount: 0,
            pageCount: 1
        )
    }

    nonisolated static func item(from record: FavoriteRecord) -> OnlineVideoItem? {
        guard let detailURL = URL(string: record.detailURL),
              OnlineSourcePolicy.allows(detailURL, source: .porny, resource: .html),
              let id = videoID(from: detailURL)
        else {
            return nil
        }
        let coverURL = record.coverURL
            .flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .porny, resource: .media) ? $0 : nil }
        return OnlineVideoItem(
            id: id,
            title: record.title,
            subtitle: record.subtitle,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 16.0 / 9.0,
            durationText: ""
        )
    }

    nonisolated static func videoID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3, parts[0] == "video", parts[1] == "view" || parts[1] == "viewhd" else { return nil }
        let id = parts[2]
        return id.isEmpty ? nil : id
    }
}
