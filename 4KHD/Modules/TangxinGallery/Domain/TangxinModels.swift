import Foundation

/// 糖心Vlog 侧边栏只固定 3 项。标签/作者/相关推荐用 `tag:` / `author:` / `related:` 深链 itemID。
nonisolated enum TangxinSection: String, CaseIterable, Identifiable {
    case latest
    case tags
    case authors

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .latest: "最近更新"
        case .tags: "分类"
        case .authors: "作者"
        }
    }

    var sidebarSystemImage: String {
        switch self {
        case .latest: "clock.arrow.circlepath"
        case .tags: "tag"
        case .authors: "person.2"
        }
    }
}

nonisolated enum TangxinRoute: Equatable {
    case latest
    case tags
    case authors
    case tag(String)
    case author(String)
    case related(String)

    var itemID: String {
        switch self {
        case .latest: TangxinSection.latest.rawValue
        case .tags: TangxinSection.tags.rawValue
        case .authors: TangxinSection.authors.rawValue
        case let .tag(slug): "tag:\(slug)"
        case let .author(name): "author:\(name)"
        case let .related(id): "related:\(id)"
        }
    }

    var title: String {
        switch self {
        case .latest: TangxinSection.latest.title
        case .tags: TangxinSection.tags.title
        case .authors: TangxinSection.authors.title
        case let .tag(slug): slug
        case let .author(name): name
        case .related: "相关推荐"
        }
    }

    var sidebarSection: TangxinSection {
        switch self {
        case .latest, .related: .latest
        case .tags, .tag: .tags
        case .authors, .author: .authors
        }
    }

    static func parse(_ itemID: String) -> TangxinRoute? {
        if let section = TangxinSection(rawValue: itemID) {
            switch section {
            case .latest: return .latest
            case .tags: return .tags
            case .authors: return .authors
            }
        }
        if let slug = value(afterPrefix: "tag:", in: itemID) {
            return .tag(slug)
        }
        if let name = value(afterPrefix: "author:", in: itemID) {
            return .author(name)
        }
        if let id = value(afterPrefix: "related:", in: itemID), id.allSatisfy(\.isNumber) {
            return .related(id)
        }
        return nil
    }

    func listURL(searchQuery: String?) -> URL? {
        if let searchQuery {
            var components = URLComponents(string: "https://tangxinvlog.app/rss.xml")
            components?.queryItems = [URLQueryItem(name: "q", value: searchQuery)]
            return components?.url
        }
        switch self {
        case .latest:
            return URL(string: "https://tangxinvlog.app/featured/")
        case .tags:
            return URL(string: "https://tangxinvlog.app/tag/")
        case .authors:
            return URL(string: "https://tangxinvlog.app/a/")
        case let .tag(slug):
            return URL(string: "https://tangxinvlog.app/tag/\(Self.encodePath(slug))/")
        case let .author(name):
            return URL(string: "https://tangxinvlog.app/a/\(Self.encodePath(name))/")
        case let .related(id):
            return URL(string: "https://tangxinvlog.app/v/\(id)/")
        }
    }

    private static func value(afterPrefix prefix: String, in itemID: String) -> String? {
        guard itemID.hasPrefix(prefix) else { return nil }
        let value = String(itemID.dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }

    private static func encodePath(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum TangxinGalleryFactory {
    @MainActor
    static func makeStore(favorites: FavoritesStore) -> OnlineVideoGalleryStore {
        OnlineVideoGalleryStore(
            policySource: .tangxin,
            sourceTitle: "糖心Vlog",
            defaultFilter: TangxinSection.latest.rawValue,
            favorites: favorites,
            listURL: { filter, query in
                TangxinRoute.parse(filter)?.listURL(searchQuery: query)
            },
            filterTitle: { TangxinRoute.parse($0)?.title ?? "糖心Vlog" },
            listResolver: TangxinListResolver.resolve,
            detailResolver: TangxinDetailResolver.resolve,
            makeFavoriteRecord: TangxinFavoritesBridge.record(from:),
            directoryFilters: [
                TangxinSection.tags.rawValue,
                TangxinSection.authors.rawValue,
            ]
        )
    }
}

enum TangxinFavoritesBridge {
    nonisolated static func record(from item: OnlineVideoItem) -> FavoriteRecord {
        FavoriteRecord(
            id: "tangxin:\(item.id)",
            sourceID: "tangxin",
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
              OnlineSourcePolicy.allows(detailURL, source: .tangxin, resource: .html),
              let id = videoID(from: detailURL)
        else {
            return nil
        }
        let coverURL = record.coverURL
            .flatMap(URL.init(string:))
            .flatMap { OnlineSourcePolicy.allows($0, source: .tangxin, resource: .media) ? $0 : nil }
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

    nonisolated static func videoID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[0] == "v" else { return nil }
        let id = parts[1]
        guard !id.isEmpty, id.allSatisfy(\.isNumber) else { return nil }
        return id
    }
}
