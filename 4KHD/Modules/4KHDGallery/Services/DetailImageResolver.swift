import AppKit
import WebKit

@MainActor
final class DetailImageResolver: NSObject, WKNavigationDelegate {
    var onResolvedPage: (ResolvedImagePage) -> Void = { _ in }
    var onFailure: (URL) -> Void = { _ in }

    private let webView: WKWebView
    private var pageURL: URL?
    private var loadedPageURL: URL?
    private var generation = UUID()
    private var webLoadGeneration: UUID?
    private var htmlResolutionTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(Self.resourceBlockingScript)

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.customUserAgent = Self.userAgent
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
    }

    deinit {
        htmlResolutionTask?.cancel()
        extractionTask?.cancel()
    }

    func cancel() {
        pageURL = nil
        cancelCurrentWork()
    }

    func resolve(pageURL: URL, force: Bool = false) {
        self.pageURL = pageURL
        guard loadedPageURL != pageURL || force else { return }
        cancelCurrentWork()

        if !force, let cached = DetailPageImageCache.shared.urls(for: pageURL) {
            loadedPageURL = pageURL
            onResolvedPage(cached)
            return
        }

        resolveHTMLFirst(pageURL: pageURL)
    }

    private func cancelCurrentWork() {
        generation = UUID()
        htmlResolutionTask?.cancel()
        htmlResolutionTask = nil
        extractionTask?.cancel()
        extractionTask = nil
        loadedPageURL = nil
        webView.stopLoading()
    }

    private func resolveHTMLFirst(pageURL: URL) {
        let currentGeneration = generation
        htmlResolutionTask?.cancel()
        htmlResolutionTask = Task { [weak self] in
            do {
                let page = try await DetailPageHTMLResolver.resolve(pageURL: pageURL)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.generation == currentGeneration else { return }
                    self.loadedPageURL = pageURL
                    self.onResolvedPage(page)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.generation == currentGeneration else { return }
                    self.loadWebFallback(pageURL: pageURL)
                }
            }
        }
    }

    private func loadWebFallback(pageURL: URL) {
        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("https://www.4khd.com/", forHTTPHeaderField: "Referer")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        webLoadGeneration = generation
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 旧导航（被 cancelCurrentWork 的 stopLoading / 新一轮 load 取代）的结果一律丢弃。
        guard webLoadGeneration == generation else { return }
        let currentGeneration = generation
        loadedPageURL = pageURL
        extractionTask?.cancel()
        extractionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
            self.extractImages(generation: currentGeneration)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webLoadGeneration == generation else { return }
        if let pageURL { onFailure(pageURL) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webLoadGeneration == generation else { return }
        if let pageURL { onFailure(pageURL) }
    }

    private func extractImages(generation: UUID) {
        webView.evaluateJavaScript(Self.extractionScript) { [weak self] result, _ in
            guard let self, let pageURL = self.pageURL else { return }
            guard self.generation == generation else { return }

            let payload = result as? [String: Any]
            let sourceURL = (payload?["sourceURL"] as? String).flatMap(URL.init(string:))
            let imageURLs = (payload?["imageURLs"] as? [String] ?? [])
                .compactMap(URL.init(string:))
                .map(GalleryImageURLNormalizer.normalized)
            let pageURLs = (payload?["pageURLs"] as? [String] ?? []).compactMap(URL.init(string:))

            guard sourceURL?.isSameDetailPath(as: pageURL) != false, !imageURLs.isEmpty else {
                self.onFailure(pageURL)
                return
            }

            let page = ResolvedImagePage(pageURL: pageURL, imageURLs: imageURLs, pageURLs: pageURLs)
            DetailPageImageCache.shared.store(page)
            self.onResolvedPage(page)
        }
    }

    private static let extractionScript = #"""
    (() => {
      const toAbsolute = (value) => {
        if (!value) return null;
        try { return new URL(value, window.location.href).href; } catch { return null; }
      };
      const allowed = (value) => {
        if (!value) return false;
        try {
          const url = new URL(value, window.location.href);
          const host = url.hostname.toLowerCase();
          return host === "pic.4khd.com" ||
            host === "img.4khd.com" ||
            (host === "i0.wp.com" && url.pathname.startsWith("/pic.4khd.com/"));
        } catch {
          return false;
        }
      };
      const root =
        document.querySelector(".entry-content, .wp-block-post-content") ||
        document.querySelector("article") ||
        document.querySelector("main") ||
        document.body;
      const imageNodes = Array.from(root.querySelectorAll("a[href] > img, a[href] picture img, figure a[href] img, img"));
      const teraBoxLink = Array.from(root.querySelectorAll("a[href]"))
        .find((node) => /terabox/i.test(node.textContent || "") || /m\.4khd\.com/i.test(node.href || ""));
      const recommendation = root.querySelector("#basicE");
      const galleryNodes = imageNodes.filter((node) => {
        if (teraBoxLink && teraBoxLink.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_PRECEDING) return false;
        if (recommendation && recommendation.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING) return false;
        const anchor = node.closest("a[href]");
        const value = toAbsolute(anchor ? anchor.getAttribute("href") : null) ||
          toAbsolute(node.currentSrc || node.src || node.getAttribute("data-src") || node.getAttribute("data-lazy-src"));
        return allowed(value) && !String(value).includes("w1090-h1500-p-k-no-rw");
      });
      const sourceNodes = galleryNodes.length >= 2 ? galleryNodes : imageNodes;
      const imageURLs = Array.from(new Set(sourceNodes
        .map((node) => {
          const anchor = node.closest("a[href]");
          return toAbsolute(anchor ? anchor.getAttribute("href") : null) ||
            toAbsolute(node.currentSrc || node.src || node.getAttribute("data-src") || node.getAttribute("data-lazy-src"));
        })
        .filter(allowed)));

      const currentPath = window.location.pathname.replace(/\/+$/, "").replace(/\/\d+$/, "");
      const sourceURL = toAbsolute(document.querySelector("link[rel='canonical']")?.getAttribute("href")) || window.location.href;
      const pageURLs = Array.from(new Set(Array.from(root.querySelectorAll("a[href]"))
        .map((node) => toAbsolute(node.getAttribute("href")))
        .filter((href) => {
          if (!href) return false;
          try {
            const url = new URL(href);
            const path = url.pathname.replace(/\/+$/, "").replace(/\/\d+$/, "");
            const host = url.hostname.toLowerCase();
            return (host === "4khd.com" || host.endsWith(".4khd.com")) && path === currentPath;
          } catch {
            return false;
          }
        })));

      return { sourceURL, imageURLs, pageURLs };
    })();
    """#

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
    private static let resourceBlockingScript = WKUserScript(
        source: #"""
        (() => {
          const removeHeavyNodes = () => {
            document.querySelectorAll("script[src], iframe, video, audio, source, link[rel='preload'], link[rel='prefetch']").forEach((node) => node.remove());
            document.querySelectorAll("img").forEach((img) => {
              img.loading = "lazy";
              img.removeAttribute("srcset");
              img.removeAttribute("sizes");
            });
          };
          removeHeavyNodes();
          new MutationObserver(removeHeavyNodes).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """#,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )
}
