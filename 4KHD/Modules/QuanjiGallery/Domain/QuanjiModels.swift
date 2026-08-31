import Foundation

/// 木瓜视频侧边栏入口。rawValue 同时作为工作区路由 itemID。
nonisolated enum QuanjiSection: String, CaseIterable, Identifiable {
    case home
    case boutique
    case amateur

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: "最近更新"
        case .boutique: "国产精品"
        case .amateur: "国产自拍"
        }
    }

    var tagID: String? {
        switch self {
        case .home: nil
        case .boutique: "5y9kg97rdzxe"
        case .amateur: "649e2zxgw10p"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .home: "clock.arrow.circlepath"
        case .boutique: "star"
        case .amateur: "video"
        }
    }

    func listURL(searchQuery: String?) -> URL? {
        if let searchQuery {
            var components = URLComponents(string: "https://91quanji.com/search.jsp")
            components?.queryItems = [URLQueryItem(name: "keyword", value: searchQuery)]
            return components?.url
        }
        switch self {
        case .home:
            return URL(string: "https://91quanji.com/")
        case .boutique, .amateur:
            guard let tagID else { return nil }
            return URL(string: "https://91quanji.com/tag.jsp?t=\(tagID)")
        }
    }
}

enum QuanjiGalleryFactory {
    @MainActor
    static func makeStore(favorites: FavoritesStore) -> OnlineVideoGalleryStore {
        OnlineVideoGalleryStore(
            policySource: .quanji,
            sourceTitle: "木瓜视频",
            defaultFilter: QuanjiSection.home.rawValue,
            favorites: favorites,
            listURL: { filter, query in
                QuanjiSection(rawValue: filter)?.listURL(searchQuery: query)
            },
            filterTitle: { QuanjiSection(rawValue: $0)?.title ?? "木瓜视频" },
            listResolver: QuanjiListResolver.resolve,
            detailResolver: QuanjiDetailResolver.resolve,
            makeFavoriteRecord: QuanjiFavoritesBridge.record(from:)
        )
    }
}

enum QuanjiFavoritesBridge {
    nonisolated static func record(from item: OnlineVideoItem) -> FavoriteRecord {
        FavoriteRecord(
            id: "quanji:\(item.id)",
            sourceID: "quanji",
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
              OnlineSourcePolicy.allows(detailURL, source: .quanji, resource: .html),
              let id = URLComponents(url: detailURL, resolvingAgainstBaseURL: false)?
              .queryItems?.first(where: { $0.name == "v" })?.value,
              !id.isEmpty
        else {
            return nil
        }
        let coverURL = record.coverURL
            .flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .quanji, resource: .media) ? $0 : nil }
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
}
