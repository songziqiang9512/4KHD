import AppKit
import Foundation

enum AppStorageFolders {
    static let imageCacheFolderName = "com.songziqiang.4khd.images"

    static var applicationSupport: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent("4KHD", isDirectory: true)
    }

    static var imageCache: URL {
        let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL.appendingPathComponent(imageCacheFolderName, isDirectory: true)
    }

    static func open(_ folderURL: URL) {
        try? FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(folderURL)
    }
}
