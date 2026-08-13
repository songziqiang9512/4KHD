import XCTest
@testable import _KHD

final class DetailPageImageCacheTests: XCTestCase {
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
}
