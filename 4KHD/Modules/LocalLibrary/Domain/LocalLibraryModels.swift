import CoreGraphics
import Foundation

struct LocalLibraryRoot: Identifiable, Hashable, Sendable {
    let url: URL
    let tree: LocalFolderNode

    var id: String { url.path }
    var title: String { url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent }
    nonisolated var imageCount: Int { tree.imageCount }
}

struct LocalFolderNode: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let folders: [LocalFolderNode]
    let images: [LocalImageItem]

    var id: String { url.path }

    nonisolated var imageCount: Int {
        images.count + folders.reduce(0) { $0 + $1.imageCount }
    }

    nonisolated var directCoverURL: URL? {
        images.first?.url
    }
}

struct LocalImageItem: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let pixelWidth: Int?
    let pixelHeight: Int?

    nonisolated var id: String { url.path }

    nonisolated var aspectRatio: CGFloat {
        guard let pixelWidth,
              let pixelHeight,
              pixelWidth > 0,
              pixelHeight > 0 else {
            return 16.0 / 9.0
        }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }
}
