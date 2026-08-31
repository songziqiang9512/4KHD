@testable import _KHD
import XCTest

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
        var galleryRequest = try URLRequest(url: XCTUnwrap(URL(string: "https://pic.4khd.com/image.jpg")))
        var missKonRequest = try URLRequest(url: XCTUnwrap(URL(string: "https://cdn.misskon.com/image.jpg")))
        var wallhavenRequest = try URLRequest(url: XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/image.jpg")))
        var knitRequest = try URLRequest(url: XCTUnwrap(URL(string: "https://r2-media.knit.bid/image.jpg")))
        var mrdsRequest = try URLRequest(url: XCTUnwrap(URL(string: "https://pic.sbhioa.cn/image.jpg")))

        GalleryRequestFactory.configureImageRequest(&galleryRequest)
        MissKonRequestFactory.configureImageRequest(&missKonRequest)
        WallhavenRequestFactory.configureImageRequest(&wallhavenRequest)
        KnitRequestFactory.configureImageRequest(&knitRequest)
        MrdsRequestFactory.configureImageRequest(&mrdsRequest)

        XCTAssertEqual(galleryRequest.value(forHTTPHeaderField: "Referer"), "https://www.4khd.com/")
        XCTAssertEqual(missKonRequest.value(forHTTPHeaderField: "Referer"), "https://misskon.com/")
        XCTAssertEqual(wallhavenRequest.value(forHTTPHeaderField: "Referer"), "https://wallhaven.cc/")
        XCTAssertEqual(knitRequest.value(forHTTPHeaderField: "Referer"), "https://xx.knit.bid/")
        XCTAssertEqual(mrdsRequest.value(forHTTPHeaderField: "Referer"), "https://www.mrds66.com/")
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

        request = URLRequest(url: evil)
        KnitRequestFactory.configureImageRequest(&request)
        XCTAssertNil(request.url)
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))

        request = URLRequest(url: evil)
        MrdsRequestFactory.configureImageRequest(&request)
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
        let knitOrigin = try XCTUnwrap(URL(string: "https://media.knit.bid/play/video.m3u8"))
        let mrdsOrigin = try XCTUnwrap(URL(string: "https://pic.sbhioa.cn/path/image.jpg"))

        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: galleryOrigin), .gallery)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: galleryRedirect), .gallery)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: missKonOrigin), .missKon)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: wallhavenOrigin), .wallhaven)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: knitOrigin), .knit)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: mrdsOrigin), .mrds)
        XCTAssertNil(OnlineSourcePolicy.source(forMediaURL: lookalike))
    }

    func testWallhavenFavoriteDetailURLExtractsOnlyTrustedWallpaperID() throws {
        let detail = try XCTUnwrap(URL(string: "https://wallhaven.cc/w/AbC123"))
        let short = try XCTUnwrap(URL(string: "https://whvn.cc/abc123"))
        let extraPath = try XCTUnwrap(URL(string: "https://wallhaven.cc/w/abc123/download"))
        let lookalike = try XCTUnwrap(URL(string: "https://wallhaven.cc.evil.example/w/abc123"))

        XCTAssertEqual(WallhavenFavoritesBridge.wallpaperID(from: detail), "abc123")
        XCTAssertEqual(WallhavenFavoritesBridge.wallpaperID(from: short), "abc123")
        XCTAssertNil(WallhavenFavoritesBridge.wallpaperID(from: extraPath))
        XCTAssertNil(WallhavenFavoritesBridge.wallpaperID(from: lookalike))
        XCTAssertEqual(
            WallhavenFavoritesBridge.originalImageCandidates(for: "AbC123").map(\.absoluteString),
            [
                "https://w.wallhaven.cc/full/ab/wallhaven-abc123.jpg",
                "https://w.wallhaven.cc/full/ab/wallhaven-abc123.png",
                "https://w.wallhaven.cc/full/ab/wallhaven-abc123.webp",
            ]
        )
        XCTAssertTrue(WallhavenFavoritesBridge.originalImageCandidates(for: "../escape").isEmpty)
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

    func testFixedSourceSessionsRejectRedirectBeforeFollowingAcrossTrustBoundaries() throws {
        let galleryHTML = try URLRequest(url: XCTUnwrap(URL(string: "https://cdn.4khd.com/content/item.html")))
        let lookalike = try URLRequest(url: XCTUnwrap(URL(string: "https://4khd.com.evil.example/content/item.html")))
        let missKonHTML = try URLRequest(url: XCTUnwrap(URL(string: "https://www.misskon.com/example/")))
        let missKonLookalike = try URLRequest(url: XCTUnwrap(URL(string: "https://misskon.com.evil.example/example/")))
        let wallhavenAPI = try URLRequest(url: XCTUnwrap(URL(string: "https://wallhaven.cc/api/v1/search")))
        let wallhavenHTML = try URLRequest(url: XCTUnwrap(URL(string: "https://wallhaven.cc/search")))
        let wallhavenMedia = try URLRequest(url: XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/ab/image.jpg")))

        XCTAssertTrue(OnlineSourceSession.galleryHTML.allowsRedirect(to: galleryHTML))
        XCTAssertFalse(OnlineSourceSession.galleryHTML.allowsRedirect(to: lookalike))
        XCTAssertTrue(OnlineSourceSession.missKonHTML.allowsRedirect(to: missKonHTML))
        XCTAssertFalse(OnlineSourceSession.missKonHTML.allowsRedirect(to: missKonLookalike))

        XCTAssertTrue(OnlineSourceSession.wallhavenAPI.allowsRedirect(to: wallhavenAPI))
        XCTAssertFalse(OnlineSourceSession.wallhavenAPI.allowsRedirect(to: wallhavenHTML))
        XCTAssertTrue(OnlineSourceSession.wallhavenHTML.allowsRedirect(to: wallhavenHTML))
        XCTAssertTrue(OnlineSourceSession.wallhavenMedia.allowsRedirect(to: wallhavenMedia))
        XCTAssertFalse(OnlineSourceSession.wallhavenMedia.allowsRedirect(to: lookalike))
    }

    func testGalleryWebFallbackMainFrameNavigationUsesHTMLAllowlist() throws {
        let initial = try XCTUnwrap(URL(string: "https://www.4khd.com/content/item.html"))
        let trustedRedirect = try XCTUnwrap(URL(string: "https://m.4khd.com/content/item.html"))
        let lookalike = try XCTUnwrap(URL(string: "https://4khd.com.evil.example/content/item.html"))

        XCTAssertTrue(DetailImageResolver.allowsWebFallbackMainFrameURL(initial))
        XCTAssertTrue(DetailImageResolver.allowsWebFallbackMainFrameURL(trustedRedirect))
        XCTAssertFalse(DetailImageResolver.allowsWebFallbackMainFrameURL(lookalike))
        XCTAssertFalse(DetailImageResolver.allowsWebFallbackMainFrameURL(nil))
    }

    func testKnitChallengeMainFrameNavigationUsesHTMLAllowlist() throws {
        let initial = try XCTUnwrap(URL(string: "https://xx.knit.bid/"))
        let trustedRedirect = try XCTUnwrap(URL(string: "https://verify.knit.bid/challenge"))
        let insecure = try XCTUnwrap(URL(string: "http://xx.knit.bid/"))
        let lookalike = try XCTUnwrap(URL(string: "https://knit.bid.evil.example/challenge"))

        XCTAssertTrue(KnitWebSessionBootstrapper.allowsChallengeMainFrameURL(initial))
        XCTAssertTrue(KnitWebSessionBootstrapper.allowsChallengeMainFrameURL(trustedRedirect))
        XCTAssertFalse(KnitWebSessionBootstrapper.allowsChallengeMainFrameURL(insecure))
        XCTAssertFalse(KnitWebSessionBootstrapper.allowsChallengeMainFrameURL(lookalike))
        XCTAssertFalse(KnitWebSessionBootstrapper.allowsChallengeMainFrameURL(nil))
    }

    func testFavoriteCoverIsRevalidatedAgainstOwningSource() {
        let trusted = FavoriteRecord(
            id: "gallery-item",
            sourceID: "latest",
            title: "Trusted",
            rawTitle: "Trusted",
            subtitle: "",
            detailURL: "https://www.4khd.com/content/example.html",
            coverURL: "https://pic.4khd.com/path/cover.jpg",
            imageCount: 1,
            pageCount: 1
        )
        let crossSource = FavoriteRecord(
            id: "gallery-item-cross-source",
            sourceID: "latest",
            title: "Cross source",
            rawTitle: "Cross source",
            subtitle: "",
            detailURL: "https://www.4khd.com/content/example.html",
            coverURL: "https://cdn.misskon.com/path/cover.jpg",
            imageCount: 1,
            pageCount: 1
        )
        let untrusted = FavoriteRecord(
            id: "gallery-item-untrusted",
            sourceID: "latest",
            title: "Untrusted",
            rawTitle: "Untrusted",
            subtitle: "",
            detailURL: "https://www.4khd.com/content/example.html",
            coverURL: "https://evil.example/path/cover.jpg",
            imageCount: 1,
            pageCount: 1
        )

        XCTAssertEqual(
            FavoriteSource.gallery.validatedCoverURL(for: trusted)?.absoluteString,
            trusted.coverURL
        )
        XCTAssertNil(FavoriteSource.gallery.validatedCoverURL(for: crossSource))
        XCTAssertNil(FavoriteSource.gallery.validatedCoverURL(for: untrusted))
        XCTAssertNil(FavoriteSource.missKon.validatedCoverURL(for: trusted))
    }
}
