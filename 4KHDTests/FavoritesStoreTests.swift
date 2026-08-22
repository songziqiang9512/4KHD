import XCTest
@testable import _KHD

final class FavoritesStoreTests: XCTestCase {
    @MainActor
    func testConcurrentTogglesAreSerializedWithoutLostUpdates() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("favorites.json")
        let backupURL = root.appendingPathComponent("favorites.json.bak")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()

        async let first = store.toggle(Self.record)
        async let second = store.toggle(Self.secondRecord)
        let results = try await (first, second)

        XCTAssertTrue(results.0)
        XCTAssertTrue(results.1)
        XCTAssertEqual(Set(store.favorites.map(\.detailURL)), [Self.record.detailURL, Self.secondRecord.detailURL])
        let persisted = try JSONDecoder().decode([FavoriteRecord].self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(Set(persisted.map(\.detailURL)), [Self.record.detailURL, Self.secondRecord.detailURL])
        XCTAssertNoThrow(try JSONDecoder().decode([FavoriteRecord].self, from: Data(contentsOf: backupURL)))
    }

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
    func testNewFavoriteIsInsertedBeforeExistingFavorites() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("favorites.json")
        try JSONEncoder().encode([Self.record]).write(to: fileURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()
        let newRecord = FavoriteRecord(
            id: "new",
            sourceID: "latest",
            title: "New",
            rawTitle: "New",
            subtitle: "",
            detailURL: "https://www.4khd.com/content/new.html",
            coverURL: nil,
            imageCount: 1,
            pageCount: 1
        )

        _ = try await store.toggle(newRecord)

        XCTAssertEqual(store.favorites.map(\.detailURL), [newRecord.detailURL, Self.record.detailURL])
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

    @MainActor
    func testLoadMergesLegacyDefaultsWhenFileAlreadyExists() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("favorites.json")
        try JSONEncoder().encode([Self.record]).write(to: fileURL)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let legacyRecord = FavoriteRecord(
            id: "legacy",
            sourceID: "misskon",
            title: "Legacy",
            rawTitle: "Legacy",
            subtitle: "Test",
            detailURL: "https://misskon.com/legacy/",
            coverURL: nil,
            imageCount: 2,
            pageCount: 1
        )
        defaults.set(try JSONEncoder().encode([Self.record, legacyRecord]), forKey: "com.songziqiang.4khd.favoriteItems.v1")

        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()

        XCTAssertEqual(store.favorites.map(\.detailURL), [Self.record.detailURL, legacyRecord.detailURL])
        let persisted = try JSONDecoder().decode([FavoriteRecord].self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(persisted.map(\.detailURL), [Self.record.detailURL, legacyRecord.detailURL])
        XCTAssertNil(defaults.data(forKey: "com.songziqiang.4khd.favoriteItems.v1"))
    }

    @MainActor
    func testRemoveAllFavoritesPersistsEmptySnapshot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("favorites.json")
        try JSONEncoder().encode([Self.record]).write(to: fileURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()
        try await store.removeAllFavorites()

        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode([FavoriteRecord].self, from: Data(contentsOf: fileURL)), [])
    }

    @MainActor
    func testCorruptFavoritesFileRecoversFromBackup() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("favorites.json")
        let backupURL = root.appendingPathComponent("favorites.json.bak")
        try Data("not-json".utf8).write(to: fileURL)
        try JSONEncoder().encode([Self.record]).write(to: backupURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))

        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()

        XCTAssertEqual(store.favorites, [Self.record])
        XCTAssertEqual(try JSONDecoder().decode([FavoriteRecord].self, from: Data(contentsOf: fileURL)), [Self.record])
    }

    func testLegacySourceIDIsRecoveredFromDetailHost() {
        let legacyMissKon = FavoriteRecord(
            id: "legacy-misskon",
            sourceID: "misskon",
            title: "Legacy MissKon",
            rawTitle: "Legacy MissKon",
            subtitle: "",
            detailURL: "https://misskon.com/legacy/",
            coverURL: nil,
            imageCount: 1,
            pageCount: 1
        )
        let legacyGallery = FavoriteRecord(
            id: "legacy-gallery",
            sourceID: "4khd",
            title: "Legacy Gallery",
            rawTitle: "Legacy Gallery",
            subtitle: "",
            detailURL: "https://www.4khd.com/legacy/",
            coverURL: nil,
            imageCount: 1,
            pageCount: 1
        )

        XCTAssertEqual(MissKonFavoritesBridge.missKonItems(from: [legacyMissKon]).count, 1)
        XCTAssertEqual(GalleryFavoritesBridge.galleryItems(from: [legacyGallery]).count, 1)
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

    private static let secondRecord = FavoriteRecord(
        id: "sample-2",
        sourceID: "misskon",
        title: "Sample 2",
        rawTitle: "Sample 2",
        subtitle: "Test",
        detailURL: "https://misskon.com/content/sample-2/",
        coverURL: nil,
        imageCount: 2,
        pageCount: 1
    )
}
