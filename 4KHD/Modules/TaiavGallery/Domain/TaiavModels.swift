import Foundation

/// TaiAV 侧边栏入口。分类 rawValue 同时是原站 `/cn/category/{名}` 路径和工作区路由 itemID。
nonisolated enum TaiavSection: String, CaseIterable, Identifiable {
    case latest
    case uncensored = "无码"
    case censored = "有码"
    case domestic = "国产AV"
    case streamers = "网红主播"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .latest: "最近更新"
        case .uncensored, .censored, .domestic, .streamers: rawValue
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .latest: "clock.arrow.circlepath"
        case .uncensored: "film"
        case .censored: "film.stack"
        case .domestic: "house"
        case .streamers: "person.wave.2"
        }
    }

    func listURL(searchQuery: String?) -> URL? {
        if let searchQuery {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "taiav.com"
            components.path = "/cn/search"
            components.queryItems = [URLQueryItem(name: "q", value: searchQuery)]
            return components.url
        }
        switch self {
        case .latest:
            return URL(string: TaiavRequestFactory.htmlOrigin)
        case .uncensored, .censored, .domestic, .streamers:
            var components = URLComponents()
            components.scheme = "https"
            components.host = "taiav.com"
            components.path = "/cn/category/\(rawValue)"
            return components.url
        }
    }
}

enum TaiavGalleryFactory {
    @MainActor
    static func makeStore(favorites: FavoritesStore) -> OnlineVideoGalleryStore {
        OnlineVideoGalleryStore(
            policySource: .taiav,
            sourceTitle: "TaiAV",
            defaultFilter: TaiavSection.latest.rawValue,
            favorites: favorites,
            listURL: { filter, query in
                TaiavSection(rawValue: filter)?.listURL(searchQuery: query)
            },
            filterTitle: { TaiavSection(rawValue: $0)?.title ?? "TaiAV" },
            listResolver: TaiavListResolver.resolve,
            detailResolver: TaiavDetailResolver.resolve,
            makeFavoriteRecord: TaiavFavoritesBridge.record(from:)
        )
    }
}

enum TaiavFavoritesBridge {
    nonisolated static func record(from item: OnlineVideoItem) -> FavoriteRecord {
        FavoriteRecord(
            id: "taiav:\(item.id)",
            sourceID: "taiav",
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
              OnlineSourcePolicy.allows(detailURL, source: .taiav, resource: .html),
              let id = movieID(from: detailURL)
        else {
            return nil
        }
        let coverURL = record.coverURL
            .flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .taiav, resource: .media) ? $0 : nil }
        return OnlineVideoItem(
            id: id,
            title: record.title,
            subtitle: record.subtitle,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 16.0 / 9.0,
            durationText: OnlineVideoItem.durationText(fromFavoriteSubtitle: record.subtitle)
        )
    }

    nonisolated static func movieID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 3,
              parts[0] == "cn",
              parts[1] == "movie",
              isMovieID(parts[2])
        else {
            return nil
        }
        return parts[2]
    }

    nonisolated static func isMovieID(_ value: String) -> Bool {
        value.count == 24 && value.allSatisfy(\.isHexDigit)
    }
}
