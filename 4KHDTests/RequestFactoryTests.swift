import XCTest
@testable import _KHD

final class RequestFactoryTests: XCTestCase {
    @MainActor
    func testWallhavenAPIRequestAddsAPIKeyAndJSONAcceptHeader() throws {
        let url = try XCTUnwrap(URL(string: "https://wallhaven.cc/api/v1/search"))

        let request = try WallhavenRequestFactory.makeAPIRequest(url: url, apiKey: "secret")

        XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 30)
    }

    @MainActor
    func testOnlineImageRequestsUseExactExpectedReferers() throws {
        var galleryRequest = URLRequest(url: try XCTUnwrap(URL(string: "https://pic.4khd.com/image.jpg")))
        var missKonRequest = URLRequest(url: try XCTUnwrap(URL(string: "https://cdn.misskon.com/image.jpg")))
        var wallhavenRequest = URLRequest(url: try XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/image.jpg")))

        GalleryRequestFactory.configureImageRequest(&galleryRequest)
        MissKonRequestFactory.configureImageRequest(&missKonRequest)
        WallhavenRequestFactory.configureImageRequest(&wallhavenRequest)

        XCTAssertEqual(galleryRequest.value(forHTTPHeaderField: "Referer"), "https://www.4khd.com/")
        XCTAssertEqual(missKonRequest.value(forHTTPHeaderField: "Referer"), "https://misskon.com/")
        XCTAssertEqual(wallhavenRequest.value(forHTTPHeaderField: "Referer"), "https://wallhaven.cc/")
    }

    func testOnlineSourcePolicyRejectsHTTPAndLookalikeHosts() throws {
        let http = try XCTUnwrap(URL(string: "http://www.4khd.com/content/item.html"))
        let lookalike = try XCTUnwrap(URL(string: "https://4khd.com.evil.example/content/item.html"))
        let localhost = try XCTUnwrap(URL(string: "https://localhost/content/item.html"))

        XCTAssertThrowsError(try GalleryRequestFactory.makeHTMLRequest(url: http))
        XCTAssertThrowsError(try GalleryRequestFactory.makeHTMLRequest(url: lookalike))
        XCTAssertThrowsError(try GalleryRequestFactory.makeHTMLRequest(url: localhost))
    }

    func testImageFactoryRejectsCrossSourceURLBeforeLoading() throws {
        let evil = try XCTUnwrap(URL(string: "https://evil.example/image.jpg"))
        var request = URLRequest(url: evil)

        GalleryRequestFactory.configureImageRequest(&request)

        XCTAssertNil(request.url)
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
    }

    func testGalleryMediaPolicyAllowsCurrentExactRedirectCDNOnly() throws {
        let currentCDN = try XCTUnwrap(URL(string: "https://yt4.googleusercontent.com/path/image.webp"))
        let thumbnailProxy = try XCTUnwrap(URL(string: "https://i0.wp.com/img.4khd.com/path/image.webp?resize=512"))
        let detailProxy = try XCTUnwrap(URL(string: "https://i0.wp.com/pic.4khd.com/path/image.webp?resize=2048"))
        let currentRedirectProxy = try XCTUnwrap(URL(string: "https://i0.wp.com/yt4.googleusercontent.com/path/image.webp"))
        let unrelatedProxy = try XCTUnwrap(URL(string: "https://i0.wp.com/evil.example/path/image.webp"))
        let siblingCDN = try XCTUnwrap(URL(string: "https://yt3.googleusercontent.com/path/image.webp"))
        let lookalike = try XCTUnwrap(URL(string: "https://yt4.googleusercontent.com.evil.example/path/image.webp"))

        XCTAssertTrue(OnlineSourcePolicy.allows(currentCDN, source: .gallery, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(thumbnailProxy, source: .gallery, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(detailProxy, source: .gallery, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(currentRedirectProxy, source: .gallery, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(unrelatedProxy, source: .gallery, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(siblingCDN, source: .gallery, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(lookalike, source: .gallery, resource: .media))
    }

    func testMediaURLResolvesExactlyOneOwningSourceWithoutReferer() throws {
        let galleryOrigin = try XCTUnwrap(URL(string: "https://pic.4khd.com/path/image.webp"))
        let galleryRedirect = try XCTUnwrap(URL(string: "https://yt4.googleusercontent.com/path/image.webp"))
        let missKonOrigin = try XCTUnwrap(URL(string: "https://cdn.misskon.com/path/image.webp"))
        let wallhavenOrigin = try XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/image.jpg"))
        let lookalike = try XCTUnwrap(URL(string: "https://pic.4khd.com.evil.example/path/image.webp"))

        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: galleryOrigin), .gallery)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: galleryRedirect), .gallery)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: missKonOrigin), .missKon)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: wallhavenOrigin), .wallhaven)
        XCTAssertNil(OnlineSourcePolicy.source(forMediaURL: lookalike))
    }

    func testResponseValidationRejectsCrossSourceRedirectTarget() throws {
        let evil = try XCTUnwrap(URL(string: "https://evil.example/content/item.html"))
        let response = try XCTUnwrap(HTTPURLResponse(url: evil, statusCode: 200, httpVersion: nil, headerFields: nil))

        XCTAssertThrowsError(
            try OnlineSourcePolicy.validate(response, source: .gallery, resource: .html)
        ) { error in
            XCTAssertEqual(error as? OnlineSourcePolicy.PolicyError, .rejectedRedirect)
        }
    }
}
