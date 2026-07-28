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
}
