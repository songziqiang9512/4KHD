import AppKit
import Foundation
import WebKit

enum KnitHTTPClientError: LocalizedError {
    case badStatus(Int)
    case challengeClosed
    case challengeTimedOut
    case pageNotReady

    var errorDescription: String? {
        switch self {
        case .badStatus(let status): "爱妹子服务器返回状态码 \(status)"
        case .challengeClosed: "访问验证窗口已关闭"
        case .challengeTimedOut: "访问验证超时"
        case .pageNotReady: "爱妹子页面尚未准备完成"
        }
    }
}

enum KnitHTTPClient {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = .shared
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 60
        // Knit 的 HTML 与 media host allowlist 当前相同；复用共享重定向门禁，
        // 在 URLSession 发出下一跳请求前拦截外域、HTTP、本机或异常端口。
        return URLSession(
            configuration: configuration,
            delegate: OnlineRedirectGuard.shared,
            delegateQueue: nil
        )
    }()

    static func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let first = try await perform(request)
        guard isChallenge(first.response) else {
            return try validated(first, request: request)
        }

        let cookies = try await KnitWebSessionBootstrapper.shared.prepare()
        let retriedRequest = KnitRequestFactory.addingCookies(cookies, to: request)
        let retry = try await perform(retriedRequest)
        return try validated(retry, request: retriedRequest)
    }

    private static func perform(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }

    private static func validated(
        _ result: (data: Data, response: HTTPURLResponse),
        request: URLRequest
    ) throws -> (Data, HTTPURLResponse) {
        try OnlineSourcePolicy.validate(result.response, source: .knit, resource: .html)
        guard (200..<300).contains(result.response.statusCode) else {
            throw KnitHTTPClientError.badStatus(result.response.statusCode)
        }
        return (result.data, result.response)
    }

    private static func isChallenge(_ response: HTTPURLResponse) -> Bool {
        response.statusCode == 403
            || response.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge"
    }
}

/// 只在 URLSession 收到 Cloudflare challenge 时出现。完成真人/托管验证后，
/// WebKit cookie 会被返回给请求重试，同时同步到应用共享 CookieStorage。
@MainActor
final class KnitWebSessionBootstrapper: NSObject, WKNavigationDelegate, NSWindowDelegate {
    static let shared = KnitWebSessionBootstrapper()

    private let challengeWindowStarter: (() -> Void)?
    private var panel: NSPanel?
    private var webView: WKWebView?
    private var inspectionTimer: Timer?
    private var timeoutTask: Task<Void, Never>?
    private var continuations: [UUID: CheckedContinuation<[HTTPCookie], Error>] = [:]
    private var isChallengeSessionActive = false
    private var isCompleting = false

    init(challengeWindowStarter: (() -> Void)? = nil) {
        self.challengeWindowStarter = challengeWindowStarter
        super.init()
    }

    func prepare() async throws -> [HTTPCookie] {
        let waiterID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                continuations[waiterID] = continuation
                startChallengeSessionIfNeeded()
            }
        }, onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(waiterID)
            }
        })
    }

    private func startChallengeSessionIfNeeded() {
        guard !isChallengeSessionActive else { return }
        isChallengeSessionActive = true
        if let challengeWindowStarter {
            challengeWindowStarter()
        } else {
            startChallengeWindow()
        }
    }

    private func startChallengeWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = KnitRequestFactory.userAgent
        self.webView = webView

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "验证爱妹子访问"
        panel.contentView = webView
        panel.contentMinSize = NSSize(width: 520, height: 420)
        panel.isReleasedWhenClosed = false
        panel.tabbingMode = .disallowed
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel

        let target = URL(string: "https://xx.knit.bid/")!
        webView.load(URLRequest(url: target, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
        inspectionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.inspectPage() }
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.finish(.failure(KnitHTTPClientError.challengeTimedOut))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, isChallengeSessionActive else { return }
        inspectPage()
    }

    nonisolated static func allowsChallengeMainFrameURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        return OnlineSourcePolicy.allows(url, source: .knit, resource: .html)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard self.webView === webView, isChallengeSessionActive else {
            decisionHandler(.cancel)
            return
        }
        // The verification panel never opens a second window. Subresources are
        // governed by WebKit, while every main-frame hop remains inside knit.bid.
        guard let targetFrame = navigationAction.targetFrame else {
            decisionHandler(.cancel)
            return
        }
        guard targetFrame.isMainFrame else {
            decisionHandler(.allow)
            return
        }
        guard Self.allowsChallengeMainFrameURL(navigationAction.request.url) else {
            decisionHandler(.cancel)
            finish(.failure(OnlineSourcePolicy.PolicyError.rejectedRedirect))
            return
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard self.webView === webView, isChallengeSessionActive else {
            decisionHandler(.cancel)
            return
        }
        guard navigationResponse.isForMainFrame else {
            decisionHandler(.allow)
            return
        }
        guard Self.allowsChallengeMainFrameURL(navigationResponse.response.url) else {
            decisionHandler(.cancel)
            finish(.failure(OnlineSourcePolicy.PolicyError.rejectedRedirect))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView, isChallengeSessionActive else { return }
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView, isChallengeSessionActive else { return }
        finish(.failure(error))
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === panel,
              !isCompleting else { return }
        finish(.failure(KnitHTTPClientError.challengeClosed))
    }

    private func inspectPage() {
        guard let webView, isChallengeSessionActive else { return }
        let script = """
        (() => ({
          host: location.hostname,
          articleCount: document.querySelectorAll('a[href*="/article/"]').length,
          challenge: /just a moment|attention required|security verification|正在验证|验证您是否是真人/i.test(document.title || '')
            || !!document.querySelector('#challenge-running, .cf-challenge, iframe[src*="challenges.cloudflare.com"]')
        }))();
        """
        webView.evaluateJavaScript(script) { [weak self] value, error in
            guard let self,
                  self.isChallengeSessionActive,
                  self.webView === webView,
                  error == nil,
                  let state = value as? [String: Any],
                  (state["host"] as? String)?.lowercased() == "xx.knit.bid",
                  (state["challenge"] as? NSNumber)?.boolValue != true,
                  ((state["articleCount"] as? NSNumber)?.intValue ?? 0) > 0 else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self,
                      self.isChallengeSessionActive,
                      self.webView === webView else { return }
                let relevant = cookies.filter { cookie in
                    let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return domain == "knit.bid" || domain.hasSuffix(".knit.bid")
                }
                for cookie in relevant {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                CookieBridge.shared.start()
                self.finish(.success(relevant))
            }
        }
    }

    private func cancelWaiter(_ waiterID: UUID) {
        guard let continuation = continuations.removeValue(forKey: waiterID) else { return }
        if continuations.isEmpty {
            stopChallengeSession()
        }
        continuation.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<[HTTPCookie], Error>) {
        guard !continuations.isEmpty else {
            stopChallengeSession()
            return
        }
        let pending = Array(continuations.values)
        continuations.removeAll()
        stopChallengeSession()
        for continuation in pending {
            continuation.resume(with: result)
        }
    }

    private func stopChallengeSession() {
        isCompleting = true
        isChallengeSessionActive = false
        inspectionTimer?.invalidate()
        inspectionTimer = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil
        isCompleting = false
    }
}
