import Foundation

enum WallhavenUploaderResolver {
    private static let apiClient = WallhavenAPIClient()

    /// Resolve wallpapers uploaded by a given username, with page support.
    /// Tries `@username` API search first; falls back to HTML scraping.
    static func resolve(username: String, page: Int, apiKey: String?) async throws -> [Wallpaper] {
        // 1. Try API search with @username (percent-encoded by URLComponents).
        let parameters = WallhavenSearchParameters(
            query: "@\(username)",
            category: .all,
            purity: .all,
            sorting: .dateAdded,
            order: .desc,
            topRange: .oneYear,
            resolution: .any,
            ratio: .any,
            page: page,
            seed: nil,
            collection: nil
        )
        if let result = try? await apiClient.search(parameters: parameters, apiKey: apiKey),
           !result.wallpapers.isEmpty {
            return result.wallpapers
        }

        // 2. Fallback: scrape the uploads page HTML for wallpaper IDs.
        guard let html = try? await fetchUploadsHTML(username: username, page: page),
              !html.isEmpty else {
            return []
        }

        let ids = extractWallpaperIDs(from: html)
        guard !ids.isEmpty else { return [] }

        // Resolve details in parallel (URLSession limits per-host concurrency to 6).
        let targetIDs = Array(ids.prefix(24))
        guard !targetIDs.isEmpty else { return [] }
        return await withTaskGroup(of: Wallpaper?.self) { group in
            for id in targetIDs {
                group.addTask {
                    try? await apiClient.wallpaper(id: id, apiKey: apiKey)
                }
            }
            var results: [Wallpaper] = []
            for await result in group {
                if let wallpaper = result { results.append(wallpaper) }
            }
            return results
        }
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
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(decoding: data, as: UTF8.self)
    }

    /// Extract wallpaper IDs from Wallhaven uploads page HTML.
    /// Wallpaper links appear as href="/w/{id}" or data-wallpaper-id="{id}".
    private static func extractWallpaperIDs(from html: String) -> [String] {
        // Match data-wallpaper-id="xxx" attributes (most reliable).
        let pattern = #"data-wallpaper-id="([a-zA-Z0-9]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)

        var seen = Set<String>()
        var ids: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let r = Range(match.range(at: 1), in: html) else { continue }
            let id = String(html[r])
            if seen.insert(id).inserted {
                ids.append(id)
            }
        }
        return ids
    }
}
