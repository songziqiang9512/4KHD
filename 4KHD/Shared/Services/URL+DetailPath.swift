import Foundation

extension URL {
    /// Raw numeric suffix used by list pagination code. Detail identity must use
    /// `detailPageNumber`, which understands each supported site's URL schema.
    nonisolated var trailingPageNumber: Int? {
        guard let last = pathComponents.last else { return nil }
        return Int(last)
    }

    /// Page number only when the URL matches a known detail-pagination shape.
    /// Numeric detail IDs (for example `/123/`) remain page 1 identities.
    nonisolated var detailPageNumber: Int? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2,
              let number = Int(components[components.count - 1]),
              number >= 2,
              let host = host?.lowercased()
        else { return nil }

        let previous = String(components[components.count - 2])
        if host == "4khd.com" || host.hasSuffix(".4khd.com") {
            return previous.lowercased().hasSuffix(".html") ? number : nil
        }
        if host == "misskon.com" || host.hasSuffix(".misskon.com")
            || host == "mrcong.com" || host.hasSuffix(".mrcong.com") {
            return Int(previous) == nil ? number : nil
        }
        return nil
    }

    nonisolated func isSameDetailPath(as other: URL) -> Bool {
        normalizedDetailPathKey == other.normalizedDetailPathKey
    }

    nonisolated var normalizedDetailPathKey: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }
        let scheme = components.scheme?.lowercased() ?? ""
        let host = components.host?.lowercased() ?? ""
        let effectivePort = components.port ?? (scheme == "https" ? 443 : (scheme == "http" ? 80 : -1))
        components.query = nil
        components.fragment = nil

        var pathParts = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if detailPageNumber != nil, !pathParts.isEmpty {
            pathParts.removeLast()
        }
        let path = "/" + pathParts.joined(separator: "/")
        return "\(scheme)://\(host):\(effectivePort)\(path)"
    }

    /// Canonical page-1 URL for a known detail-pagination URL.
    nonisolated var canonicalDetailPageURL: URL {
        guard detailPageNumber != nil,
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else { return self }
        var parts = components.percentEncodedPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !parts.isEmpty else { return self }
        parts.removeLast()
        components.percentEncodedPath = "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url ?? self
    }
}
