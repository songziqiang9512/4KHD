import Foundation

enum WorkspaceSidebarNode: Hashable {
    case group(String)
    case gallery(GallerySection)
    case missKon(MissKonSection)
    case wallhaven(WallhavenSection)
    case knit(KnitSidebarSection)
    case localAllImages(count: Int)
    case localFolder(LocalFolderNode)
    case favoritesModule

    var title: String {
        switch self {
        case .group(let title):
            title
        case .gallery(let section):
            section.title
        case .missKon(let section):
            section.title
        case .wallhaven(let section):
            section.title
        case .knit(let section):
            section.title
        case .localAllImages:
            "我的图片"
        case .localFolder(let folder):
            folder.title
        case .favoritesModule:
            "在线收藏"
        }
    }

    var stateIdentifier: String {
        switch self {
        case .group(let title):
            "group:\(title)"
        case .gallery(let section):
            "gallery:\(section.rawValue)"
        case .missKon(let section):
            "missKon:\(section.rawValue)"
        case .wallhaven(let section):
            "wallhaven:\(section.rawValue)"
        case .knit(let section):
            "knit:\(section.rawValue)"
        case .localAllImages:
            "local:allImages"
        case .localFolder(let folder):
            "localFolder:\(folder.id)"
        case .favoritesModule:
            "favorites:all"
        }
    }

    var count: Int? {
        switch self {
        case .localAllImages(let count):
            count
        case .localFolder(let folder):
            folder.imageCount
        default:
            nil
        }
    }
}
