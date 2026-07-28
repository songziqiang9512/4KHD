import XCTest
@testable import _KHD

final class FavoritesStoreTests: XCTestCase {
    @MainActor
    func testTogglePersistsBeforePublishingState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("favorites.json")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()

        let isFavorite = try await store.toggle(Self.record)

        XCTAssertTrue(isFavorite)
        XCTAssertEqual(store.favorites, [Self.record])
        let data = try Data(contentsOf: fileURL)
        XCTAssertEqual(try JSONDecoder().decode([FavoriteRecord].self, from: data), [Self.record])
    }

    @MainActor
    func testToggleKeepsOldStateWhenPersistenceFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingFile = root.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFile)
        let invalidFileURL = blockingFile.appendingPathComponent("favorites.json")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: invalidFileURL, defaults: defaults)
        await store.waitUntilLoaded()

        do {
            _ = try await store.toggle(Self.record)
            XCTFail("Expected persistence to fail")
        } catch {
            XCTAssertEqual(error as? FavoritesStoreError, .persistenceFailed)
        }

        XCTAssertTrue(store.favorites.isEmpty)
    }

    private static let record = FavoriteRecord(
        id: "sample",
        sourceID: "4khd",
        title: "Sample",
        rawTitle: "Sample",
        subtitle: "Test",
        detailURL: "https://www.4khd.com/content/sample.html",
        coverURL: nil,
        imageCount: 1,
        pageCount: 1
    )
}
