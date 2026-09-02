import Foundation

enum WorkspaceSidebarNode: Hashable {
    case group(String)
    case gallery(GallerySection)
    case missKon(MissKonSection)
    case wallhaven(WallhavenSection)
    case knit(KnitSidebarSection)
    case mrds(MrdsSection)
    case quanji(QuanjiSection)
    case porny(PornySection)
    case tangxin(TangxinSection)
    case taiav(TaiavSection)
    case localAllImages(count: Int)
    case localFolder(LocalFolderNode)
    case favoritesModule

    var title: String {
        switch self {
        case let .group(title):
            title
        case let .gallery(section):
            section.title
        case let .missKon(section):
            section.title
        case let .wallhaven(section):
            section.title
        case let .knit(section):
            section.title
        case let .mrds(section):
            section.title
        case let .quanji(section):
            section.title
        case let .porny(section):
            section.title
        case let .tangxin(section):
            section.title
        case let .taiav(section):
            section.title
        case .localAllImages:
            "我的图片"
        case let .localFolder(folder):
            folder.title
        case .favoritesModule:
            "我的收藏"
        }
    }

    var stateIdentifier: String {
        switch self {
        case let .group(title):
            "group:\(title)"
        case let .gallery(section):
            "gallery:\(section.rawValue)"
        case let .missKon(section):
            "missKon:\(section.rawValue)"
        case let .wallhaven(section):
            "wallhaven:\(section.rawValue)"
        case let .knit(section):
            "knit:\(section.rawValue)"
        case let .mrds(section):
            "mrds:\(section.rawValue)"
        case let .quanji(section):
            "quanji:\(section.rawValue)"
        case let .porny(section):
            "porny:\(section.rawValue)"
        case let .tangxin(section):
            "tangxin:\(section.rawValue)"
        case let .taiav(section):
            "taiav:\(section.rawValue)"
        case .localAllImages:
            "local:allImages"
        case let .localFolder(folder):
            "localFolder:\(folder.id)"
        case .favoritesModule:
            "favorites:all"
        }
    }

    var count: Int? {
        switch self {
        case let .localAllImages(count):
            count
        case let .localFolder(folder):
            folder.imageCount
        default:
            nil
        }
    }

    var groupMediaSymbolName: String? {
        guard case let .group(title) = self else { return nil }
        switch title {
        case "木瓜视频", "91PORNY", "糖心Vlog", "TaiAV":
            return "play.rectangle"
        default:
            return "photo.stack"
        }
    }
}
