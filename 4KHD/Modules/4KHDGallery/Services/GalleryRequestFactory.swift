import Foundation

enum GalleryRequestFactory {
    nonisolated static func makeHTMLRequest(url: URL, cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.cachePolicy = cachePolicy
        configureCommonHeaders(&request)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    nonisolated static func configureImageRequest(_ request: inout URLRequest) {
        configureCommonHeaders(&request)
        request.setValue("image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
    }

    private nonisolated static func configureCommonHeaders(_ request: inout URLRequest) {
        request.setValue("https://www.4khd.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
    }
}
