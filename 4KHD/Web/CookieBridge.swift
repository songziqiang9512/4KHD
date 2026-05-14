import Foundation
import WebKit

/// 把 `WKWebsiteDataStore.default()` 里的 cookie（含 CloudFlare 的 `cf_clearance` 等）
/// 同步给 `HTTPCookieStorage.shared`。`URLSession.shared` 默认就是从后者读 cookie，
/// 同步之后子页面解析走 URLSession 直拉也能带上同一张 CF 票，大部分情况下不再需要
/// 退到 WKWebView fallback。
///
/// 同步双向触发：
/// 1. 启动时全量拉一次 WebKit cookie 写入 `HTTPCookieStorage.shared`；
/// 2. WebKit cookie 后续变化（页面加载完拿到新 token）时由 observer 增量同步；
/// 3. 反方向：URLSession 拿到响应里的 Set-Cookie 时，写回 WebKit store，
///    保证两边一致。
@MainActor
final class CookieBridge: NSObject {
    static let shared = CookieBridge()

    private let webKitStore: WKHTTPCookieStore
    private let cookieSyncQueue = DispatchQueue(label: "com.songziqiang.4khd.cookie-sync", qos: .utility)
    private var didStart = false

    override private init() {
        self.webKitStore = WKWebsiteDataStore.default().httpCookieStore
        super.init()
    }

    /// 在 App 早期调用一次。重复调用安全。
    func start() {
        guard !didStart else { return }
        didStart = true
        webKitStore.add(self)
        // 启动时已有的 WebKit cookie 先全量灌一遍。
        syncFromWebKit()
        // 反向：当前 HTTPCookieStorage.shared 里已有的 cookie 也推一遍给 WebKit，
        // 让两边状态在启动时就对齐。
        syncToWebKit()
    }

    /// 把 WKWebsiteDataStore 当前所有 cookie 同步到 HTTPCookieStorage.shared。
    func syncFromWebKit() {
        let cookieSyncQueue = cookieSyncQueue
        webKitStore.getAllCookies { cookies in
            cookieSyncQueue.async {
                for cookie in cookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
            }
        }
    }

    /// 把 HTTPCookieStorage.shared 当前所有 cookie 同步到 WKWebsiteDataStore。
    func syncToWebKit() {
        let webKitStore = webKitStore
        cookieSyncQueue.async {
            let cookies = HTTPCookieStorage.shared.cookies ?? []
            DispatchQueue.main.async {
                for cookie in cookies {
                    webKitStore.setCookie(cookie)
                }
            }
        }
    }
}

// MARK: - WKHTTPCookieStoreObserver

extension CookieBridge: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            self.syncFromWebKit()
        }
    }
}
