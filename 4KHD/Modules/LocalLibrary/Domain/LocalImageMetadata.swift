import Foundation
import ImageIO

struct LocalImageMetadata: Sendable {
    let fileSize: Int64?
    let modifiedDate: Date?
    let pixelWidth: Int?
    let pixelHeight: Int?
    let fileExists: Bool
}

func formattedResolution(_ metadata: LocalImageMetadata?) -> String? {
    guard let metadata else { return nil }
    guard let pixelWidth = metadata.pixelWidth, let pixelHeight = metadata.pixelHeight else {
        return nil
    }
    return "\(pixelWidth)×\(pixelHeight)"
}

func formattedSecondaryMetadata(_ metadata: LocalImageMetadata?) -> String? {
    guard let metadata else { return nil }
    var parts: [String] = []
    if let fileSize = metadata.fileSize {
        parts.append(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

nonisolated func pixelSize(for url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return nil
    }

    let width = properties[kCGImagePropertyPixelWidth] as? Int
    let height = properties[kCGImagePropertyPixelHeight] as? Int
    guard let width, let height else { return nil }
    return (width, height)
}
