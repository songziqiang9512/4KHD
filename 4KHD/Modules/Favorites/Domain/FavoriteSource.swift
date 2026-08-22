import Foundation

/// 收藏记录的来源模块。判定以 detailURL 的 host 为准:
/// `FavoriteRecord.sourceID` 是各模块 section 的 rawValue(Gallery/MissKon 两边都有
/// "cosplay" 等重名),不可靠。白名单与三个 FavoritesBridge 的 isAllowedHost 保持一致。
enum FavoriteSource: String, CaseIterable {
    case gallery
    case missKon
    case wallhaven

    var title: String {
        switch self {
        case .gallery: "4KHD"
        case .missKon: "MissKon"
        case .wallhaven: "Wallhaven"
        }
    }

    var systemImage: String {
        switch self {
        case .gallery: "photo.on.rectangle"
        case .missKon: "person.crop.square"
        case .wallhaven: "photo.stack"
        }
    }

    /// 具体来源的请求配置由 App 组装层注册,Favorites 不直接依赖业务模块。
    @MainActor
    var imageRequestConfigurator: ((inout URLRequest) -> Void)? {
        FavoriteSourceAdapterRegistry.shared.adapter(for: self)?.configureImageRequest
    }

    static func source(for record: FavoriteRecord) -> FavoriteSource? {
        guard let url = URL(string: record.detailURL) else { return nil }
        if OnlineSourcePolicy.allows(url, source: .gallery, resource: .html) { return .gallery }
        if OnlineSourcePolicy.allows(url, source: .missKon, resource: .html) { return .missKon }
        if OnlineSourcePolicy.allows(url, source: .wallhaven, resource: .html) { return .wallhaven }
        return nil
    }
}

/// 统一收藏模块的来源筛选(rawValue 同时作路由 itemID)。
enum FavoriteSourceFilter: String, CaseIterable {
    case all
    case gallery
    case missKon
    case wallhaven

    var title: String {
        switch self {
        case .all: "全部"
        case .gallery: "4KHD"
        case .missKon: "MissKon"
        case .wallhaven: "Wallhaven"
        }
    }

    var source: FavoriteSource? {
        switch self {
        case .all: nil
        case .gallery: .gallery
        case .missKon: .missKon
        case .wallhaven: .wallhaven
        }
    }
}
