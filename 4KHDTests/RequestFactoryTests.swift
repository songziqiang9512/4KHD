import XCTest
@testable import _KHD

final class RequestFactoryTests: XCTestCase {
    @MainActor
    func testWallhavenAPIRequestAddsAPIKeyAndJSONAcceptHeader() throws {
        let url = try XCTUnwrap(URL(string: "https://wallhaven.cc/api/v1/search"))

        let request = WallhavenRequestFactory.makeAPIRequest(url: url, apiKey: "secret")

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 30)
    }

    @MainActor
    func testOnlineImageRequestsUseExactExpectedReferers() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/image.jpg"))
        var galleryRequest = URLRequest(url: url)
        var missKonRequest = URLRequest(url: url)
        var wallhavenRequest = URLRequest(url: url)

        GalleryRequestFactory.configureImageRequest(&galleryRequest)
        MissKonRequestFactory.configureImageRequest(&missKonRequest)
        WallhavenRequestFactory.configureImageRequest(&wallhavenRequest)

        XCTAssertEqual(galleryRequest.value(forHTTPHeaderField: "Referer"), "https://www.4khd.com/")
        XCTAssertEqual(missKonRequest.value(forHTTPHeaderField: "Referer"), "https://misskon.com/")
        XCTAssertEqual(wallhavenRequest.value(forHTTPHeaderField: "Referer"), "https://wallhaven.cc/")
    }
}
