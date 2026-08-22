import Foundation

enum WallhavenRequestFactory {
    private nonisolated static let userAgent = "4KHD macOS/1.0 (Wallhaven API Client)"

    nonisolated static func makeAPIRequest(url: URL, apiKey: String? = nil) throws -> URLRequest {
        try OnlineSourcePolicy.validate(url, source: .wallhaven, resource: .api)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return request
    }

    nonisolated static func configureImageRequest(_ request: inout URLRequest) {
        guard let url = request.url,
              OnlineSourcePolicy.allows(url, source: .wallhaven, resource: .media) else {
            request.url = nil
            return
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://wallhaven.cc/", forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
    }
}
