import XCTest
@testable import _KHD

final class DetailPageImageCacheTests: XCTestCase {
    func testDetailIdentityIncludesOriginAndEffectivePort() throws {
        let base = try XCTUnwrap(URL(string: "https://www.4khd.com/content/sample.html"))
        let explicitDefaultPort = try XCTUnwrap(URL(string: "https://www.4khd.com:443/content/sample.html"))
        let differentHost = try XCTUnwrap(URL(string: "https://evil.example/content/sample.html"))
        let differentScheme = try XCTUnwrap(URL(string: "http://www.4khd.com/content/sample.html"))
        let differentPort = try XCTUnwrap(URL(string: "https://www.4khd.com:444/content/sample.html"))

        XCTAssertTrue(base.isSameDetailPath(as: explicitDefaultPort))
        XCTAssertFalse(base.isSameDetailPath(as: differentHost))
        XCTAssertFalse(base.isSameDetailPath(as: differentScheme))
        XCTAssertFalse(base.isSameDetailPath(as: differentPort))
    }

    func testDetailIdentityStripsOnlyKnownPaginationSegments() throws {
        let galleryBase = try XCTUnwrap(URL(string: "https://www.4khd.com/content/sample.html"))
        let galleryPage = try XCTUnwrap(URL(string: "https://www.4khd.com/content/sample.html/2"))
        let missKonBase = try XCTUnwrap(URL(string: "https://misskon.com/sample-set/"))
        let missKonPage = try XCTUnwrap(URL(string: "https://misskon.com/sample-set/8/"))
        let numericDetail = try XCTUnwrap(URL(string: "https://misskon.com/123/"))
        let differentNumericDetail = try XCTUnwrap(URL(string: "https://misskon.com/456/"))

        XCTAssertTrue(galleryBase.isSameDetailPath(as: galleryPage))
        XCTAssertEqual(galleryPage.detailPageNumber, 2)
        XCTAssertTrue(missKonBase.isSameDetailPath(as: missKonPage))
        XCTAssertEqual(missKonPage.detailPageNumber, 8)
        XCTAssertNil(numericDetail.detailPageNumber)
        XCTAssertFalse(numericDetail.isSameDetailPath(as: differentNumericDetail))
    }

    @MainActor
    func testClearPreventsInitialDiskSnapshotFromReappearing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("pages.json")
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/content/sample.html"))
        let imageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/sample.jpg"))

        let writer = DetailPageImageCache(cacheURL: cacheURL)
        writer.store(pageURL: pageURL, imageURLs: [imageURL], pageURLs: [pageURL])
        writer.flush()

        let cache = DetailPageImageCache(cacheURL: cacheURL)
        try await cache.clear()

        XCTAssertNil(cache.page(for: pageURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    func testMissKonMetadataCachePreservesKnownMissingDownloadLink() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("metadata.json")
        let pageURL = try XCTUnwrap(URL(string: "https://misskon.com/sample/"))

        let writer = MissKonDetailMetadataCache(cacheURL: cacheURL)
        XCTAssertNil(writer.metadata(for: pageURL))
        writer.store(pageURL: pageURL, mediaFireURL: nil)
        writer.flush()

        let reader = MissKonDetailMetadataCache(cacheURL: cacheURL)
        let metadata = try XCTUnwrap(reader.metadata(for: pageURL))
        XCTAssertNil(metadata.mediaFireURL)
    }
}
