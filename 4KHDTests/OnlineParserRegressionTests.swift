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
