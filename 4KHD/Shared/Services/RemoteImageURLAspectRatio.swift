import Foundation

/// Best-effort dimensions encoded in common image resize URLs. Callers must
/// still replace this hint with decoded image dimensions when available.
nonisolated enum RemoteImageURLAspectRatio {
    private static let resizeRegex = regex(#"(?:\?|&)resize=([0-9]+)(?:%2C|,)([0-9]+)"#)
    private static let pathSizeRegex = regex(#"/w([0-9]+)-h([0-9]+)-"#)

    static func aspectRatio(from url: URL) -> Double? {
        let absoluteString = url.absoluteString
        return aspectRatio(matching: resizeRegex, in: absoluteString)
            ?? aspectRatio(matching: pathSizeRegex, in: absoluteString)
    }

    private static func aspectRatio(matching regex: NSRegularExpression, in value: String) -> Double? {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 2,
              let widthRange = Range(match.range(at: 1), in: value),
              let heightRange = Range(match.range(at: 2), in: value),
              let width = Double(value[widthRange]),
              let height = Double(value[heightRange]),
              width > 0,
              height > 0 else {
            return nil
        }
        return width / height
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        } catch {
            preconditionFailure("Invalid regex pattern: \(pattern)")
        }
    }
}
