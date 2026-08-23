import XCTest
@testable import _KHD

final class OnlineParserRegressionTests: XCTestCase {
    @MainActor
    func testGalleryNonSearchListRejectsUnrecognizedMarkup() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/"))

        XCTAssertThrowsError(
            try SiteListResolver.parse(
                html: "<html><body>unexpected layout</body></html>",
                pageURL: pageURL,
                section: .latest
            )
        ) { error in
            XCTAssertEqual(error as? SiteListResolverError, .unrecognizedListMarkup)
        }
    }

    @MainActor
    func testMissKonNonSearchListRejectsUnrecognizedMarkup() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://misskon.com/"))

        XCTAssertThrowsError(
            try MissKonListResolver.parse(
                html: "<html><body>unexpected layout</body></html>",
                pageURL: pageURL,
                section: .latest
            )
        ) { error in
            XCTAssertEqual(error as? MissKonListResolverError, .unrecognizedListMarkup)
        }
    }

    @MainActor
    func testMissKonEmptySearchPreservesExplicitNextPage() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://misskon.com/?s=missing"))
        let html = #"<div class="no-results"></div><a class="page-numbers next" href="/page/2/?s=missing">Next</a>"#

        let page = try MissKonListResolver.parse(
            html: html,
            pageURL: pageURL,
            section: .latest,
            allowsEmptyResults: true
        )

        XCTAssertTrue(page.items.isEmpty)
        XCTAssertEqual(page.nextPageURL?.path, "/page/2")
    }

    @MainActor
    func testGalleryLatestPaginationUsesRealPageLinkWhenPresent() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/"))
        let html = #"""
        <link rel="next" href="https://www.4khd.com/page/2">
        <li class="wp-block-post"><a href="https://www.4khd.com/content/test.html">Test</a></li>
        <span class="page-numbers current">1</span>
        <a class="page-numbers" href="https://www.4khd.com/?query-3-page=2">2</a>
        """#

        let page = try SiteListResolver.parse(html: html, pageURL: pageURL, section: .latest)

        XCTAssertEqual(page.nextPageURL?.absoluteString, "https://www.4khd.com/?query-3-page=2")
    }

    @MainActor
    func testGalleryLatestPaginationTerminatesOnLastPage() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/"))
        let html = #"""
        <li class="wp-block-post"><a href="https://www.4khd.com/content/test.html">Test</a></li>
        <span class="page-numbers current">5</span>
        <a class="page-numbers" href="https://www.4khd.com/?query-3-page=2">2</a>
        """#

        let page = try SiteListResolver.parse(html: html, pageURL: pageURL, section: .latest)

        XCTAssertNil(page.nextPageURL)
    }

    @MainActor
    func testGalleryLatestPaginationFallsBackToIncrementWithoutPageLinks() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/"))
        let html = #"""
        <link rel="next" href="https://www.4khd.com/page/4">
        <li class="wp-block-post"><a href="https://www.4khd.com/content/test.html">Test</a></li>
        <span class="page-numbers current">3</span>
        """#

        let page = try SiteListResolver.parse(html: html, pageURL: pageURL, section: .latest)

        XCTAssertEqual(page.nextPageURL?.absoluteString, "https://www.4khd.com/?query-3-page=4")
    }

    @MainActor
    func testMissKonPageURLsNormalizeTrailingSlash() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://misskon.com/"))
        // 详情 href 无尾部斜杠：分页 URL 必须归一为 /post-name/2/ 而不是 /post-name2/。
        let html = #"""
        <article class="item-list">
        <h2 class="post-box-title"><a href="https://misskon.com/post-name">Test (24 photos)</a></h2>
        <img src="https://misskon.com/cover.jpg">
        </article>
        """#

        let page = try MissKonListResolver.parse(html: html, pageURL: pageURL, section: .latest)

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].pageURLs.count, 2)
        XCTAssertEqual(page.items[0].pageURLs[1].absoluteString, "https://misskon.com/post-name/2/")
    }

    @MainActor
    func testMediaFireDownloadLinkExtractedFromDetailHTML() throws {
        // 真实详情页片段:ouo.io 短链 + 紧随其后的 Terabox 链接。
        let html = #"""
        <p style="text-align: center"><a href="https://ouo.io/AWhxx8" target="_blank" class="shortc-button medium green "><i class="fa fa fa-download"></i>Download link: MediaFire</a> <p style="text-align: center"><a href="https://1024terabox.com/s/171mfLkllv8Z1JSoKo9lP0Q" target="_blank" class="shortc-button medium blue "><i class="fa fa fa-download"></i>Download link: Terabox</a>
        """#

        let url = MissKonDetailResolver.extractMediaFireDownloadLink(from: html)
        XCTAssertEqual(url?.absoluteString, "https://ouo.io/AWhxx8")

        // 无 MediaFire 按钮时返回 nil。
        let withoutButton = MissKonDetailResolver.extractMediaFireDownloadLink(
            from: "<p><a href=\"https://example.com/x\">Download link: Terabox</a></p>"
        )
        XCTAssertNil(withoutButton)
    }

    func testGalleryRecommendationsAreParsedOutsideImageContent() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/content/current.html"))
        let html = #"""
        <div id="basicE">
          <a href="/content/related.html">
            <img src="https://pic.4khd.com/related.webp" />
            <p>Related &#8211; Set[195MB-30photos]</p>
          </a>
          <a href="https://evil.example/content/rejected.html">
            <img src="https://evil.example/rejected.jpg" /><p>Rejected[1MB-1photos]</p>
          </a>
        </div>
        """#

        let recommendations = DetailPageHTMLResolver.extractRecommendations(from: html, pageURL: pageURL)

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations[0].title, "Related - Set")
        XCTAssertEqual(recommendations[0].imageCount, 30)
        XCTAssertEqual(recommendations[0].detailURL.absoluteString, "https://www.4khd.com/content/related.html")
        XCTAssertEqual(recommendations[0].coverURL?.absoluteString, "https://pic.4khd.com/related.webp")
    }

    func testMissKonYARPPRecommendationsAreParsedAndDeduplicated() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://misskon.com/current-set/"))
        let card = #"""
        <a class='yarpp-thumbnail' href='/related-set/' title='Related Set (93 photos)'>
          <img width="306" height="163" src="data:image/svg+xml,placeholder"
               data-src="https://misskon.com/media/related.webp" />
          <span class="yarpp-thumbnail-title">Related &#8211; Set (93 photos)</span>
        </a>
        """#
        let html = card + card + #"<a href="https://misskon.com/not-yarpp/">Ignore</a>"#

        let recommendations = MissKonDetailResolver.extractRecommendations(from: html, pageURL: pageURL)

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations[0].title, "Related - Set")
        XCTAssertEqual(recommendations[0].imageCount, 93)
        XCTAssertEqual(recommendations[0].detailURL.absoluteString, "https://misskon.com/related-set/")
        XCTAssertEqual(recommendations[0].coverURL?.absoluteString, "https://misskon.com/media/related.webp")
        XCTAssertEqual(recommendations[0].coverAspectRatio ?? 0, 306.0 / 163.0, accuracy: 0.0001)
    }
}

final class WallhavenFavoritesBridgeTests: XCTestCase {
    @MainActor
    func testPurityIsRestoredFromSubtitle() throws {
        let record = FavoriteRecord(
            id: "w1",
            sourceID: "wallhaven",
            title: "Test",
            rawTitle: "w1",
            subtitle: "1920 x 1080 · image/png · NSFW",
            detailURL: "https://wallhaven.cc/w/w1",
            coverURL: "https://w.wallhaven.cc/full/ab/wallhaven-w1.jpg",
            imageCount: 1,
            pageCount: 1
        )

        let wallpapers = WallhavenFavoritesBridge.wallpapers(from: [record])

        XCTAssertEqual(wallpapers.first?.purity, .nsfw)
    }

    @MainActor
    func testPurityDefaultsToSFWWithoutSubtitleMatch() throws {
        let record = FavoriteRecord(
            id: "w2",
            sourceID: "wallhaven",
            title: "Test",
            rawTitle: "w2",
            subtitle: "1920 x 1080",
            detailURL: "https://wallhaven.cc/w/w2",
            coverURL: nil,
            imageCount: 1,
            pageCount: 1
        )

        let wallpapers = WallhavenFavoritesBridge.wallpapers(from: [record])

        XCTAssertEqual(wallpapers.first?.purity, .sfw)
    }
}
