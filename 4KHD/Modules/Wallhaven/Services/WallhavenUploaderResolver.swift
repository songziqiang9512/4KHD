import Foundation

enum WallhavenUploaderResolver {
    private static let apiClient = WallhavenAPIClient()

    enum ResolverError: LocalizedError {
        case detailsUnavailable

        var errorDescription: String? {
            switch self {
            case .detailsUnavailable:
                "Wallhaven 作品详情加载失败，请稍后重试"
            }
        }
    }

    /// Resolve wallpapers uploaded by a given username, with page support.
    /// Tries `@username` API search first; falls back to HTML scraping.
    /// Throws only when both API and HTML scraping fail (network error).
    /// Returns empty array when author has no uploads or page is beyond last.
    static func resolve(username: String, page: Int, purity: WallhavenPurity, apiKey: String?) async throws -> [Wallpaper] {
        // 1. Try API search with @username, respecting the user's purity setting.
        let parameters = WallhavenSearchParameters(
            query: "@\(username)",
            category: .all,
            purity: purity,
            sorting: .dateAdded,
            order: .desc,
            topRange: .oneYear,
            resolution: .any,
            ratio: .any,
            page: page,
            seed: nil,
            collection: nil
        )
        let searchError: Error?
        do {
            let result = try await apiClient.search(parameters: parameters, apiKey: apiKey)
            if !result.wallpapers.isEmpty {
                return result.wallpapers
            }
            searchError = nil
        } catch {
            searchError = error
        }

        // 2. Fallback: scrape the uploads page HTML for wallpaper IDs.
        // Use try (not try?) so network failures propagate to feed store catch → retry UI.
        let html = try await fetchUploadsHTML(username: username, page: page)
        guard !html.isEmpty else {
            if let searchError { throw searchError }
            return []
        }

        let ids = extractWallpaperIDs(from: html)
        guard !ids.isEmpty else {
            if let searchError { throw searchError }
            return []
        }

        // Resolve details in parallel, preserving page order.
        // Limit to 16 IDs and 4 concurrent to avoid hammering the API.
        let targetIDs = Array(ids.prefix(16))
        guard !targetIDs.isEmpty else { return [] }
        let wallpapers = await withTaskGroup(of: Wallpaper?.self) { group in
            var cursor = 0
            var running = 0
            var byID: [String: Wallpaper] = [:]
            while cursor < targetIDs.count || running > 0 {
                while running < 4, cursor < targetIDs.count {
                    let id = targetIDs[cursor]
                    cursor += 1
                    running += 1
                    group.addTask {
                        try? await apiClient.wallpaper(id: id, apiKey: apiKey)
                    }
                }
                guard let result = await group.next() else { break }
                running -= 1
                if let wallpaper = result { byID[wallpaper.id] = wallpaper }
            }
            return targetIDs.compactMap { byID[$0] }
        }
        guard !wallpapers.isEmpty else {
            if let searchError { throw searchError }
            throw ResolverError.detailsUnavailable
        }
        return wallpapers
    }

    // MARK: - HTML scraping

    private static func fetchUploadsHTML(username: String, page: Int) async throws -> String {
        let urlString = page <= 1
            ? "https://wallhaven.cc/user/\(username)/uploads"
            : "https://wallhaven.cc/user/\(username)/uploads?page=\(page)"
        guard let url = URL(string: urlString) else {
            throw WallhavenAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("4KHD macOS/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WallhavenAPIError.decodingFailed
        }
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 404:
            return ""
        case 401:
            throw WallhavenAPIError.unauthorized
        case 429:
            throw WallhavenAPIError.rateLimited
        default:
            throw WallhavenAPIError.badStatus(httpResponse.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Extract wallpaper IDs from Wallhaven uploads page HTML, preserving page order.
    /// Matches data-wallpaper-id="{id}", href="/w/{id}", or href="https://wallhaven.cc/w/{id}".
    private static func extractWallpaperIDs(from html: String) -> [String] {
        let patterns: [(String, Int)] = [
            (#"data-wallpaper-id="([a-zA-Z0-9]+)""#, 1),
            (#"href="(?:https://wallhaven\.cc)?/w/([a-zA-Z0-9]+)""#, 1)
        ]
        // Collect (location, id) tuples, sort by location, then dedup.
        var entries: [(location: Int, id: String)] = []
        for (pattern, groupIndex) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, options: [], range: range) {
                guard match.numberOfRanges > groupIndex,
                      let r = Range(match.range(at: groupIndex), in: html) else { continue }
                entries.append((match.range.location, String(html[r])))
            }
        }
        entries.sort { $0.location < $1.location }
        var seen = Set<String>()
        return entries.compactMap {
            seen.insert($0.id).inserted ? $0.id : nil
        }
    }
}
