import Foundation

enum TangxinRequestFactory {
    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    nonisolated static let htmlOrigin = "https://tangxinvlog.app/"

    static func makeHTMLRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    ) throws -> URLRequest {
        try OnlineSourcePolicy.validate(url, source: .tangxin, resource: .html)
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 60)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(htmlOrigin, forHTTPHeaderField: "Referer")
        return request
    }

    nonisolated static func configureImageRequest(_ request: inout URLRequest) {
        guard let url = request.url,
              OnlineSourcePolicy.allows(url, source: .tangxin, resource: .media)
        else {
            request.url = nil
            return
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(htmlOrigin, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
    }
}

enum TangxinHTTPClientError: LocalizedError {
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .badStatus(status): "糖心Vlog 服务器返回状态码 \(status)"
        }
    }
}

enum TangxinHTTPClient {
    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await OnlineSourceSession.tangxinHTML.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw TangxinHTTPClientError.badStatus(response.statusCode)
        }
        return (data, response)
    }
}
