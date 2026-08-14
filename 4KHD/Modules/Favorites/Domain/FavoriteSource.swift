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

    /// 封面加载所需的请求头配置(Referer 等),与各模块自己的 RemoteImageView 一致。
    var imageRequestConfigurator: ((inout URLRequest) -> Void)? {
        switch self {
        case .gallery: GalleryRequestFactory.configureImageRequest
        case .missKon: MissKonRequestFactory.configureImageRequest
        case .wallhaven: WallhavenRequestFactory.configureImageRequest
        }
    }

    static func source(for record: FavoriteRecord) -> FavoriteSource? {
        guard let url = URL(string: record.detailURL),
              let host = url.host?.lowercased() else { return nil }
        if host == "4khd.com" || host.hasSuffix(".4khd.com") { return .gallery }
        if host == "misskon.com" || host.hasSuffix(".misskon.com") { return .missKon }
        if host == "wallhaven.cc" || host == "whvn.cc" || host.hasSuffix(".wallhaven.cc") { return .wallhaven }
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
