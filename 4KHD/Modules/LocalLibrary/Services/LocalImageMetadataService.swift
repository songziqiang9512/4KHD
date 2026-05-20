import Foundation

enum LocalImageMetadataService {
    static func loadMetadata(for images: [LocalImageItem]) async -> [LocalImageItem.ID: LocalImageMetadata] {
        await Task.detached(priority: .utility) {
            var result: [LocalImageItem.ID: LocalImageMetadata] = [:]
            let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
            for image in images {
                guard !Task.isCancelled else { return result }
                let values = try? image.url.resourceValues(forKeys: keys)
                result[image.id] = LocalImageMetadata(
                    fileSize: values?.fileSize.map(Int64.init),
                    modifiedDate: values?.contentModificationDate,
                    pixelWidth: image.pixelWidth,
                    pixelHeight: image.pixelHeight,
                    fileExists: FileManager.default.fileExists(atPath: image.url.path)
                )
            }
            return result
        }.value
    }

    static func loadAvailability(for images: [LocalImageItem]) async -> [LocalImageItem.ID: Bool] {
        await Task.detached(priority: .utility) {
            Dictionary(uniqueKeysWithValues: images.map { image in
                (image.id, FileManager.default.fileExists(atPath: image.url.path))
            })
        }.value
    }
}
