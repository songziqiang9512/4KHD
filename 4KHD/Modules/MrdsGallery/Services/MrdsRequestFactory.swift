import Foundation

enum MrdsRequestFactory {
    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
    nonisolated static let htmlOrigin = "https://www.mrds66.com/"

    static func makeHTMLRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
    ) throws -> URLRequest {
        try OnlineSourcePolicy.validate(url, source: .mrds, resource: .html)
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: 45)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(htmlOrigin, forHTTPHeaderField: "Referer")
        return request
    }

    nonisolated static func configureImageRequest(_ request: inout URLRequest) {
        MrdsImageDecryptor.prepare()
        guard let url = request.url,
              OnlineSourcePolicy.allows(url, source: .mrds, resource: .media)
        else {
            request.url = nil
            return
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(htmlOrigin, forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
    }
}
