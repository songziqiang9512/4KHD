import Foundation

enum TaiavRequestFactory {
    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    nonisolated static let htmlOrigin = "https://taiav.com/cn"
    nonisolated static let mediaOrigin = "https://img.storyofthepast.xyz"

    static func makeHTMLRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    ) throws -> URLRequest {
        try OnlineSourcePolicy.validate(url, source: .taiav, resource: .html)
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 45)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(htmlOrigin, forHTTPHeaderField: "Referer")
        return request
    }

    static func makeGetMovieRequest(movieID: String, pageURL: URL) throws -> URLRequest {
        guard TaiavFavoritesBridge.isMovieID(movieID),
              let url = getMovieURL(movieID: movieID)
        else {
            throw TaiavDetailResolverError.invalidMovie
        }
        try OnlineSourcePolicy.validate(url, source: .taiav, resource: .api)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 45)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json,text/plain,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(pageURL.absoluteString, forHTTPHeaderField: "Referer")
        return request
    }

    nonisolated static func getMovieURL(movieID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "taiav.com"
        components.path = "/api/getmovie"
        components.queryItems = [
            URLQueryItem(name: "type", value: "1280"),
            URLQueryItem(name: "id", value: movieID),
        ]
        return components.url
    }

    nonisolated static func configureImageRequest(_ request: inout URLRequest) {
        guard let url = request.url,
              OnlineSourcePolicy.allows(url, source: .taiav, resource: .media)
        else {
            request.url = nil
            return
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(htmlOrigin, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
    }
}

enum TaiavHTTPClientError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .badStatus(status): "TaiAV 服务器返回状态码 \(status)"
        }
    }
}

enum TaiavHTTPClient {
    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await OnlineSourceSession.taiavHTML.data(for: request)
        return try validated(data: data, response: response)
    }

    static func apiData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await OnlineSourceSession.taiavAPI.data(for: request)
        return try validated(data: data, response: response)
    }

    private static func validated(data: Data, response: URLResponse) throws -> (Data, HTTPURLResponse) {
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw TaiavHTTPClientError.badStatus(response.statusCode)
        }
        return (data, response)
    }
}
