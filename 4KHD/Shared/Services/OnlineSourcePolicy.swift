import Foundation
import OSLog

enum OnlineSourcePolicy {
    enum Source: String {
        case gallery
        case missKon
        case wallhaven
        case knit
        case mrds
        case quanji
        case porny
        case tangxin
    }

    enum Resource {
        case html
        case api
        case media
    }

    enum PolicyError: LocalizedError, Equatable {
        case rejectedURL
        case rejectedRedirect

        var errorDescription: String? {
            switch self {
            case .rejectedURL: "在线资源地址不在受信任来源范围内"
            case .rejectedRedirect: "在线请求被重定向到不受信任的来源"
            }
        }
    }

    nonisolated static func validate(_ url: URL, source: Source, resource: Resource) throws {
        guard allows(url, source: source, resource: resource) else {
            throw PolicyError.rejectedURL
        }
    }

    nonisolated static func validate(_ response: URLResponse, source: Source, resource: Resource) throws {
        guard let finalURL = response.url,
              allows(finalURL, source: source, resource: resource)
        else {
            throw PolicyError.rejectedRedirect
        }
    }

    nonisolated static func allows(_ url: URL, source: Source, resource: Resource) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.port == nil || url.port == 443,
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              !host.isEmpty else { return false }

        switch (source, resource) {
        case (.gallery, .html):
            return isExactOrSubdomain(host, of: "4khd.com")
        case (.gallery, .media):
            return host == "pic.4khd.com"
                || host == "img.4khd.com"
                // pic.4khd.com currently redirects its Google-hosted originals
                // to this exact CDN host. Keep this narrow: do not allow the
                // whole googleusercontent.com suffix.
                || host == "yt4.googleusercontent.com"
                || (host == "i0.wp.com"
                    && (url.path.hasPrefix("/pic.4khd.com/")
                        || url.path.hasPrefix("/img.4khd.com/")
                        || url.path.hasPrefix("/yt4.googleusercontent.com/")))
        case (.gallery, .api):
            return false
        case (.missKon, .html):
            return isExactOrSubdomain(host, of: "misskon.com")
                || isExactOrSubdomain(host, of: "mrcong.com")
        case (.missKon, .media):
            return isExactOrSubdomain(host, of: "misskon.com")
                || isExactOrSubdomain(host, of: "mrcong.com")
        case (.missKon, .api):
            return false
        case (.wallhaven, .api):
            return host == "wallhaven.cc" && url.path.hasPrefix("/api/v1/")
        case (.wallhaven, .html):
            return host == "wallhaven.cc" || host == "www.wallhaven.cc" || host == "whvn.cc"
        case (.wallhaven, .media):
            return isExactOrSubdomain(host, of: "wallhaven.cc")
        case (.knit, .html):
            return isExactOrSubdomain(host, of: "knit.bid")
        case (.knit, .media):
            return isExactOrSubdomain(host, of: "knit.bid")
        case (.knit, .api):
            return false
        case (.mrds, .html):
            return isExactOrSubdomain(host, of: "mrds66.com")
        case (.mrds, .media):
            return host == "pic.sbhioa.cn"
                || host == "hls.piotrt.cn"
                || host == "ts.syjiaotong.mobi"
                || host == "tx.doudou520.online"
                || host == "ts.zhixunkeji.xyz"
        case (.mrds, .api):
            return false
        case (.quanji, .html):
            return isExactOrSubdomain(host, of: "91quanji.com")
        case (.quanji, .media):
            return isExactOrSubdomain(host, of: "mugua01.cfd")
                || isExactOrSubdomain(host, of: "o9hx3f-s8jamrmtps5.sbs")
        case (.quanji, .api):
            return false
        case (.porny, .html):
            return isExactOrSubdomain(host, of: "91porny.com")
        case (.porny, .media):
            return host == "int.ucloud161.xyz"
                || host == "int.qiniuyun37.xyz"
                || isExactOrSubdomain(host, of: "jiuse3.cloud")
        case (.porny, .api):
            return false
        case (.tangxin, .html):
            return isExactOrSubdomain(host, of: "tangxinvlog.app")
        case (.tangxin, .media):
            return host == "t.5gcdn.xyz"
        case (.tangxin, .api):
            return false
        }
    }

    /// Resolves the owning module from a URL that has already passed a
    /// source-specific media allowlist. This is used by URLSession redirect
    /// delegates because some image loaders do not retain custom Referer
    /// headers on `task.originalRequest`.
    nonisolated static func source(forMediaURL url: URL) -> Source? {
        let matches = [Source.gallery, .missKon, .wallhaven, .knit, .mrds, .quanji, .porny, .tangxin].filter {
            allows(url, source: $0, resource: .media)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    nonisolated static func resolvedURL(
        _ value: String,
        relativeTo baseURL: URL,
        source: Source,
        resource: Resource
    ) -> URL? {
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              allows(url, source: source, resource: resource) else { return nil }
        return url
    }

    private nonisolated static func isExactOrSubdomain(_ host: String, of domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    nonisolated static func originHeader(fromReferer referer: String) -> String? {
        guard let url = URL(string: referer),
              let scheme = url.scheme,
              let host = url.host
        else { return nil }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }
}

/// Nuke owns its URLSession, so redirect validation is installed on its data
/// loader delegate. Prefer the request Referer, then fall back to the original
/// media URL's exact source allowlist because URLSession/Nuke may omit custom
/// headers from `task.originalRequest`.
final class OnlineRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = OnlineRedirectGuard()
    private nonisolated static let logger = Logger(
        subsystem: "com.songziqiang.4khd",
        category: "OnlineRedirectGuard"
    )

    nonisolated func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @Sendable @escaping (URLRequest?) -> Void
    ) {
        let source = source(for: task)
        let targetURL = request.url
        guard let source,
              let targetURL,
              OnlineSourcePolicy.allows(targetURL, source: source, resource: .media)
        else {
            let originalHost = task.originalRequest?.url?.host ?? "<none>"
            let currentHost = task.currentRequest?.url?.host ?? "<none>"
            let targetHost = targetURL?.host ?? "<none>"
            let sourceName = source?.rawValue ?? "<none>"
            Self.logger.error(
                "Blocked media redirect: original=\(originalHost, privacy: .public) current=\(currentHost, privacy: .public) target=\(targetHost, privacy: .public) source=\(sourceName, privacy: .public)"
            )
            completionHandler(nil)
            return
        }
        completionHandler(Self.requestByPreservingMediaHeaders(from: task.originalRequest, onto: request))
    }

    private nonisolated func source(for task: URLSessionTask) -> OnlineSourcePolicy.Source? {
        let requests = [task.originalRequest, task.currentRequest].compactMap { $0 }
        for request in requests {
            if let source = source(fromRefererOf: request) {
                return source
            }
            if let url = request.url,
               let source = OnlineSourcePolicy.source(forMediaURL: url)
            {
                return source
            }
        }
        return nil
    }

    private nonisolated func source(fromRefererOf request: URLRequest) -> OnlineSourcePolicy.Source? {
        guard let referer = request.value(forHTTPHeaderField: "Referer"),
              let url = URL(string: referer),
              let host = url.host?.lowercased() else { return nil }
        if host == "4khd.com" || host.hasSuffix(".4khd.com") { return .gallery }
        if host == "misskon.com" || host.hasSuffix(".misskon.com") { return .missKon }
        if host == "wallhaven.cc" || host.hasSuffix(".wallhaven.cc") { return .wallhaven }
        if host == "knit.bid" || host.hasSuffix(".knit.bid") { return .knit }
        if host == "mrds66.com" || host.hasSuffix(".mrds66.com") { return .mrds }
        if host == "91quanji.com" || host.hasSuffix(".91quanji.com") { return .quanji }
        if host == "91porny.com" || host.hasSuffix(".91porny.com") { return .porny }
        if host == "tangxinvlog.app" || host.hasSuffix(".tangxinvlog.app") { return .tangxin }
        return nil
    }

    /// URLSession rewrites Referer on cross-path redirects. Media CDNs that
    /// gate on the HTML origin would then 403, so keep the original UA/Referer/Origin.
    nonisolated static func requestByPreservingMediaHeaders(
        from original: URLRequest?,
        onto redirected: URLRequest
    ) -> URLRequest {
        guard let original else { return redirected }
        var request = redirected
        for header in ["User-Agent", "Referer", "Origin"] {
            if let value = original.value(forHTTPHeaderField: header) {
                request.setValue(value, forHTTPHeaderField: header)
            }
        }
        return request
    }
}

/// URLSession client whose redirect policy is fixed at construction time.
///
/// HTML/API probes must reject an untrusted redirect before URLSession follows
/// it. The configuration deliberately shares the app cookie jar (including
/// cookies bridged from WebKit) while disabling URLCache as a disk layer.
final class OnlineSourceSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let galleryHTML = OnlineSourceSession(source: .gallery, resource: .html)
    static let missKonHTML = OnlineSourceSession(source: .missKon, resource: .html)
    static let wallhavenAPI = OnlineSourceSession(source: .wallhaven, resource: .api)
    static let wallhavenHTML = OnlineSourceSession(source: .wallhaven, resource: .html)
    static let wallhavenMedia = OnlineSourceSession(source: .wallhaven, resource: .media)
    static let mrdsHTML = OnlineSourceSession(source: .mrds, resource: .html)
    static let quanjiHTML = OnlineSourceSession(source: .quanji, resource: .html)
    static let pornyHTML = OnlineSourceSession(source: .porny, resource: .html)
    static let tangxinHTML = OnlineSourceSession(source: .tangxin, resource: .html)

    private let source: OnlineSourcePolicy.Source
    private let resource: OnlineSourcePolicy.Resource
    private var session: URLSession!

    private init(source: OnlineSourcePolicy.Source, resource: OnlineSourcePolicy.Resource) {
        self.source = source
        self.resource = resource
        super.init()

        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            throw OnlineSourcePolicy.PolicyError.rejectedURL
        }
        try OnlineSourcePolicy.validate(url, source: source, resource: resource)
        let result = try await session.data(for: request)
        try OnlineSourcePolicy.validate(result.1, source: source, resource: resource)
        return result
    }

    nonisolated func allowsRedirect(to request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return OnlineSourcePolicy.allows(url, source: source, resource: resource)
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @Sendable @escaping (URLRequest?) -> Void
    ) {
        completionHandler(allowsRedirect(to: request) ? request : nil)
    }
}
