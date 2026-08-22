import Foundation

enum MissKonRequestFactory {
    private nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"

    nonisolated static func makeHTMLRequest(url: URL, cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad) throws -> URLRequest {
        try OnlineSourcePolicy.validate(url, source: .missKon, resource: .html)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = cachePolicy
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("https://misskon.com/", forHTTPHeaderField: "Referer")
        return request
    }

    nonisolated static func configureImageRequest(_ request: inout URLRequest) {
        guard let url = request.url,
              OnlineSourcePolicy.allows(url, source: .missKon, resource: .media) else {
            request.url = nil
            return
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://misskon.com/", forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
    }
}
