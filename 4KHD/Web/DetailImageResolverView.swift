import SwiftUI
import WebKit

struct DetailImageResolverView: NSViewRepresentable {
    let pageURL: URL
    let onResolvedPage: (ResolvedImagePage) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = Self.userAgent
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.pageURL = pageURL
        context.coordinator.onResolvedPage = onResolvedPage
        context.coordinator.onFailure = onFailure

        guard context.coordinator.loadedPageURL != pageURL else { return }
        context.coordinator.cancelCurrentWork(in: webView)

        if let cached = DetailPageImageCache.shared.urls(for: pageURL) {
            onResolvedPage(cached)
            return
        }

        var request = URLRequest(url: pageURL)
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("https://www.4khd.com/", forHTTPHeaderField: "Referer")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        webView.load(request)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var pageURL: URL?
        var loadedPageURL: URL?
        var onResolvedPage: (ResolvedImagePage) -> Void = { _ in }
        var onFailure: () -> Void = {}
        private var generation = UUID()
        private var extractionTask: Task<Void, Never>?

        func cancelCurrentWork(in webView: WKWebView) {
            generation = UUID()
            extractionTask?.cancel()
            extractionTask = nil
            loadedPageURL = nil
            webView.stopLoading()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let currentGeneration = generation
            loadedPageURL = pageURL
            extractionTask?.cancel()
            extractionTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, self.generation == currentGeneration else { return }
                self.extractImages(from: webView, generation: currentGeneration)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onFailure()
        }

        private func extractImages(from webView: WKWebView, generation: UUID) {
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
                    self.onFailure()
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
            const lower = value.toLowerCase();
            return lower.includes("pic.4khd.com") || lower.includes("img.4khd.com") || lower.includes("i0.wp.com");
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
                return url.hostname.includes("4khd.com") && path === currentPath;
              } catch {
                return false;
              }
            })));

          return { sourceURL, imageURLs, pageURLs };
        })();
        """#
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
}

enum LocalDetailHTMLStore {
    nonisolated static func html(for pageURL: URL, bundle: Bundle = .main) -> String? {
        guard pageURL.trailingPageNumber == nil else { return nil }
        let slug = pageURL.deletingPathExtension().lastPathComponent
        guard !slug.isEmpty else { return nil }
        let name = "detail-\(slug)"
        let candidates = [
            bundle.url(forResource: name, withExtension: "html", subdirectory: "ApifyCapture"),
            bundle.url(forResource: name, withExtension: "html"),
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Scripts/outputs/4khd_site_capture/\(name).html")
        ].compactMap { $0 }

        for url in candidates {
            guard let html = try? String(contentsOf: url, encoding: .utf8) else { continue }
            return html
        }
        return nil
    }
}

extension URL {
    nonisolated var trailingPageNumber: Int? {
        guard let last = pathComponents.last else { return nil }
        return Int(last)
    }

    nonisolated func isSameDetailPath(as other: URL) -> Bool {
        normalizedDetailPath == other.normalizedDetailPath
    }

    private nonisolated var normalizedDetailPath: String {
        let path = trailingPageNumber == nil ? self.path : deletingLastPathComponent().path
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
