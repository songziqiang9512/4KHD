import Foundation

extension URL {
    nonisolated var trailingPageNumber: Int? {
        guard let last = pathComponents.last else { return nil }
        return Int(last)
    }

    nonisolated func isSameDetailPath(as other: URL) -> Bool {
        normalizedDetailPathKey == other.normalizedDetailPathKey
    }

    nonisolated var normalizedDetailPathKey: String {
        let path = trailingPageNumber == nil ? self.path : deletingLastPathComponent().path
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
