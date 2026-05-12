import Foundation

struct LocalLibraryRoot: Identifiable, Hashable {
    let url: URL
    let tree: LocalFolderNode

    var id: String { url.path }
    var title: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    var imageCount: Int { tree.imageCount }
}

struct LocalFolderNode: Identifiable, Hashable {
    let url: URL
    let title: String
    let folders: [LocalFolderNode]
    let images: [LocalImageItem]

    var id: String { url.path }

    var imageCount: Int {
        images.count + folders.reduce(0) { $0 + $1.imageCount }
    }

    var coverURL: URL? {
        images.first?.url ?? folders.lazy.compactMap(\.coverURL).first
    }
}

struct LocalImageItem: Identifiable, Hashable {
    let url: URL
    let title: String

    var id: String { url.path }
}
