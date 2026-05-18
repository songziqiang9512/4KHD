import Foundation

enum WorkspaceSidebarNode: Hashable {
    case group(String)
    case gallery(GallerySection)
    case importLocal
    case localFolder(LocalFolderNode)

    var title: String {
        switch self {
        case .group(let title):
            title
        case .gallery(let section):
            section.title
        case .importLocal:
            "导入本地目录"
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
        case .importLocal:
            "local:import"
        case .localFolder(let folder):
            "localFolder:\(folder.id)"
        }
    }
}
