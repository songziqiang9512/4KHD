import Foundation

enum WorkspaceSidebarNode: Hashable {
    case group(String)
    case gallery(GallerySection)
    case missKon(MissKonSection)
    case wallhaven(WallhavenSection)
    case localAllImages(count: Int)
    case localFolder(LocalFolderNode)

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
        case .localAllImages:
            "我的图片"
        case .localFolder(let folder):
            folder.title
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
        case .localAllImages:
            "local:allImages"
        case .localFolder(let folder):
            "localFolder:\(folder.id)"
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
