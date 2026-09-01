import Foundation

/// 收藏记录的来源模块。判定以 detailURL 的 host 为准:
/// `FavoriteRecord.sourceID` 是各模块 section 的 rawValue(Gallery/MissKon 两边都有
/// "cosplay" 等重名),不可靠。白名单与三个 FavoritesBridge 的 isAllowedHost 保持一致。
enum FavoriteSource: String, CaseIterable {
    case gallery
    case missKon
    case wallhaven
    case knit
    case mrds
    case quanji
    case porny
    case tangxin

    var title: String {
        switch self {
        case .gallery: "4KHD"
        case .missKon: "MissKon"
        case .wallhaven: "Wallhaven"
        case .knit: "爱妹子"
        case .mrds: "每日大赛"
        case .quanji: "木瓜视频"
        case .porny: "91PORNY"
        case .tangxin: "糖心Vlog"
        }
    }

    var systemImage: String {
        switch self {
        case .gallery: "photo.on.rectangle"
        case .missKon: "person.crop.square"
        case .wallhaven: "photo.stack"
        case .knit: "photo.on.rectangle.angled"
        case .mrds: "flag.checkered"
        case .quanji: "play.rectangle"
        case .porny: "play.tv"
        case .tangxin: "play.rectangle.on.rectangle"
        }
    }

    /// 具体来源的请求配置由 App 组装层注册,Favorites 不直接依赖业务模块。
    @MainActor
    var imageRequestConfigurator: ((inout URLRequest) -> Void)? {
        FavoriteSourceAdapterRegistry.shared.adapter(for: self)?.configureImageRequest
    }

    /// Old/imported favorite records are not trusted to carry a source-owned
    /// cover. Validate both the detail owner and the media URL before attaching
    /// source-specific request headers or starting an image request.
    nonisolated func validatedCoverURL(for record: FavoriteRecord) -> URL? {
        guard Self.source(for: record) == self,
              let url = record.coverURL.flatMap(URL.init(string:)),
              OnlineSourcePolicy.allows(url, source: policySource, resource: .media)
        else {
            return nil
        }
        return url
    }

    private nonisolated var policySource: OnlineSourcePolicy.Source {
        switch self {
        case .gallery: .gallery
        case .missKon: .missKon
        case .wallhaven: .wallhaven
        case .knit: .knit
        case .mrds: .mrds
        case .quanji: .quanji
        case .porny: .porny
        case .tangxin: .tangxin
        }
    }

    nonisolated static func source(for record: FavoriteRecord) -> FavoriteSource? {
        guard let url = URL(string: record.detailURL) else { return nil }
        if OnlineSourcePolicy.allows(url, source: .gallery, resource: .html) { return .gallery }
        if OnlineSourcePolicy.allows(url, source: .missKon, resource: .html) { return .missKon }
        if OnlineSourcePolicy.allows(url, source: .wallhaven, resource: .html) { return .wallhaven }
        if OnlineSourcePolicy.allows(url, source: .knit, resource: .html) { return .knit }
        if OnlineSourcePolicy.allows(url, source: .mrds, resource: .html) { return .mrds }
        if OnlineSourcePolicy.allows(url, source: .quanji, resource: .html) { return .quanji }
        if OnlineSourcePolicy.allows(url, source: .porny, resource: .html) { return .porny }
        if OnlineSourcePolicy.allows(url, source: .tangxin, resource: .html) { return .tangxin }
        return nil
    }
}

/// 统一收藏模块的来源筛选(rawValue 同时作路由 itemID)。
enum FavoriteSourceFilter: String, CaseIterable {
    case all
    case gallery
    case missKon
    case wallhaven
    case knit
    case mrds
    case quanji
    case porny
    case tangxin

    var title: String {
        switch self {
        case .all: "全部"
        case .gallery: "4KHD"
        case .missKon: "MissKon"
        case .wallhaven: "Wallhaven"
        case .knit: "爱妹子"
        case .mrds: "每日大赛"
        case .quanji: "木瓜视频"
        case .porny: "91PORNY"
        case .tangxin: "糖心Vlog"
        }
    }

    var source: FavoriteSource? {
        switch self {
        case .all: nil
        case .gallery: .gallery
        case .missKon: .missKon
        case .wallhaven: .wallhaven
        case .knit: .knit
        case .mrds: .mrds
        case .quanji: .quanji
        case .porny: .porny
        case .tangxin: .tangxin
        }
    }
}
