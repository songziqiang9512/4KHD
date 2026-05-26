import Foundation

enum WallhavenUploaderResolver {
    private static let apiClient = WallhavenAPIClient()

    /// Resolve wallpapers uploaded by a given username.
    /// Tries `@username` API search first; falls back to HTML scraping.
    static func resolve(username: String, apiKey: String?) async throws -> [Wallpaper] {
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
            page: 1,
            seed: nil,
            collection: nil
        )
        if let page = try? await apiClient.search(parameters: parameters, apiKey: apiKey),
           !page.wallpapers.isEmpty {
            return page.wallpapers
        }

        // 2. Fallback: scrape the uploads page HTML for wallpaper IDs.
        guard let html = try? await fetchUploadsHTML(username: username),
              !html.isEmpty else {
            return []
        }

        let ids = extractWallpaperIDs(from: html)
        guard !ids.isEmpty else { return [] }

        // Resolve details for each ID (limit to first 24 to avoid too many requests).
        var results: [Wallpaper] = []
        for id in ids.prefix(24) {
            if let wallpaper = try? await apiClient.wallpaper(id: id, apiKey: apiKey) {
                results.append(wallpaper)
            }
        }
        return results
    }

    // MARK: - HTML scraping

    private static func fetchUploadsHTML(username: String) async throws -> String {
        let urlString = "https://wallhaven.cc/user/\(username)/uploads"
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
