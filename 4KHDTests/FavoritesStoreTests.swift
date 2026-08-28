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

    @MainActor
    func testKnitFavoriteExportImportRoundTripPreservesAllFields() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDefaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let destinationDefaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let sourceStore = FavoritesStore(
            fileURL: root.appendingPathComponent("source-favorites.json"),
            defaults: sourceDefaults
        )
        await sourceStore.waitUntilLoaded()
        _ = try await sourceStore.toggle(Self.knitRecord)

        let exportURL = root.appendingPathComponent("favorites-export.json")
        try await sourceStore.exportFavorites(to: exportURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(
            FavoritesStore.BackupFile.self,
            from: Data(contentsOf: exportURL)
        )
        XCTAssertEqual(backup.formatVersion, 1)
        XCTAssertEqual(backup.favorites, [Self.knitRecord])

        let destinationStore = FavoritesStore(
            fileURL: root.appendingPathComponent("destination-favorites.json"),
            defaults: destinationDefaults
        )
        await destinationStore.waitUntilLoaded()
        let result = try await destinationStore.importFavorites(from: exportURL)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(destinationStore.favorites, [Self.knitRecord])
        XCTAssertEqual(FavoriteSource.source(for: try XCTUnwrap(destinationStore.favorites.first)), .knit)

        let moduleStore = FavoritesModuleStore(favoritesStore: destinationStore)
        moduleStore.setFilter(.knit)
        XCTAssertEqual(moduleStore.visibleRecords, [Self.knitRecord])
    }

    @MainActor
    func testImportAcceptsOnlySupportedHTTPSDetailURLs() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"), defaults: defaults)
        await store.waitUntilLoaded()

        let rejected = [
            Self.makeRecord(id: "http", detailURL: "http://xx.knit.bid/article/1/"),
            Self.makeRecord(id: "lookalike", detailURL: "https://knit.bid.evil.example/article/2/"),
            Self.makeRecord(id: "unsupported", detailURL: "https://example.com/article/3/"),
            Self.makeRecord(id: "relative", detailURL: "article/4/")
        ]
        let importURL = root.appendingPathComponent("unsupported-favorites.json")
        try JSONEncoder().encode([Self.knitRecord] + rejected).write(to: importURL)

        let result = try await store.importFavorites(from: importURL)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.skippedCount, rejected.count)
        XCTAssertEqual(store.favorites, [Self.knitRecord])
    }

    @MainActor
    func testImportSanitizesCoverURLUsingDetailSourceMediaAllowlist() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"), defaults: defaults)
        await store.waitUntilLoaded()

        let validCover = "https://pic.4khd.com/import-valid.jpg"
        let records = [
            Self.makeRecord(
                id: "valid-cover",
                detailURL: "https://www.4khd.com/content/import-valid.html",
                coverURL: validCover
            ),
            Self.makeRecord(
                id: "cross-source-cover",
                detailURL: "https://www.4khd.com/content/import-cross-source.html",
                coverURL: "https://misskon.com/media/cross-source.jpg"
            ),
            Self.makeRecord(
                id: "http-cover",
                detailURL: "https://www.4khd.com/content/import-http.html",
                coverURL: "http://pic.4khd.com/insecure.jpg"
            ),
            Self.makeRecord(
                id: "lookalike-cover",
                detailURL: "https://www.4khd.com/content/import-lookalike.html",
                coverURL: "https://pic.4khd.com.evil.example/lookalike.jpg"
            ),
        ]
        let importURL = root.appendingPathComponent("cover-policy.json")
        try JSONEncoder().encode(records).write(to: importURL)

        let result = try await store.importFavorites(from: importURL)

        XCTAssertEqual(result.addedCount, records.count)
        XCTAssertEqual(result.updatedCount, 0)
        XCTAssertEqual(result.skippedCount, 0)
        let importedByID = Dictionary(uniqueKeysWithValues: store.favorites.map { ($0.id, $0) })
        XCTAssertEqual(importedByID["valid-cover"]?.coverURL, validCover)
        XCTAssertNil(importedByID["cross-source-cover"]?.coverURL)
        XCTAssertNil(importedByID["http-cover"]?.coverURL)
        XCTAssertNil(importedByID["lookalike-cover"]?.coverURL)
    }

    @MainActor
    func testImportDeduplicatesStableAndUsesLastRecordContents() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("favorites.json")
        let existingFirst = Self.makeRecord(
            id: "existing-first", title: "Existing First", detailURL: "https://xx.knit.bid/article/10/"
        )
        let existingLast = Self.makeRecord(
            id: "existing-last", title: "Existing Last", detailURL: existingFirst.detailURL
        )
        try JSONEncoder().encode([existingFirst, existingLast]).write(to: fileURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()

        let addedFirst = Self.makeRecord(
            id: "added-first", title: "Added First", detailURL: "https://xx.knit.bid/article/20/"
        )
        let existingImportedLast = Self.makeRecord(
            id: "existing-imported-last", title: "Existing Imported Last", detailURL: existingFirst.detailURL
        )
        let addedLast = Self.makeRecord(
            id: "added-last", title: "Added Last", detailURL: addedFirst.detailURL
        )
        let importURL = root.appendingPathComponent("duplicates.json")
        try JSONEncoder().encode([addedFirst, existingImportedLast, addedLast]).write(to: importURL)

        let result = try await store.importFavorites(from: importURL)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.updatedCount, 2)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(store.favorites, [existingImportedLast, addedLast])
        XCTAssertEqual(
            try JSONDecoder().decode([FavoriteRecord].self, from: Data(contentsOf: fileURL)),
            [existingImportedLast, addedLast]
        )
    }

    @MainActor
    func testLegacyMergeDeduplicatesEachInputWithoutChangingStableOrder() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("favorites.json")
        let fileFirst = Self.makeRecord(
            id: "file-first", title: "File First", detailURL: "https://xx.knit.bid/article/30/"
        )
        let fileLast = Self.makeRecord(
            id: "file-last", title: "File Last", detailURL: fileFirst.detailURL
        )
        try JSONEncoder().encode([fileFirst, fileLast]).write(to: fileURL)

        let legacyFirst = Self.makeRecord(
            id: "legacy-first", title: "Legacy First", detailURL: "https://xx.knit.bid/article/40/"
        )
        let legacyLast = Self.makeRecord(
            id: "legacy-last", title: "Legacy Last", detailURL: legacyFirst.detailURL
        )
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "4KHDTests-\(UUID().uuidString)"))
        defaults.set(
            try JSONEncoder().encode([fileFirst, legacyFirst, legacyLast]),
            forKey: "com.songziqiang.4khd.favoriteItems.v1"
        )

        let store = FavoritesStore(fileURL: fileURL, defaults: defaults)
        await store.waitUntilLoaded()

        XCTAssertEqual(store.favorites, [fileLast, legacyLast])
        XCTAssertEqual(
            try JSONDecoder().decode([FavoriteRecord].self, from: Data(contentsOf: fileURL)),
            [fileLast, legacyLast]
        )
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

    private static let knitRecord = FavoriteRecord(
        id: "knit:32463",
        sourceID: "knit",
        title: "爱妹子标题",
        rawTitle: "Knit Raw Title",
        subtitle: "丝袜美女 · 21P · 1V",
        detailURL: "https://xx.knit.bid/article/32463/",
        coverURL: "https://r2-media.knit.bid/static/images/32463/cover.jpg",
        imageCount: 21,
        pageCount: 3
    )

    private static func makeRecord(
        id: String,
        title: String? = nil,
        detailURL: String,
        coverURL: String? = nil
    ) -> FavoriteRecord {
        FavoriteRecord(
            id: id,
            sourceID: "knit",
            title: title ?? id,
            rawTitle: "Raw \(title ?? id)",
            subtitle: "Test",
            detailURL: detailURL,
            coverURL: coverURL,
            imageCount: 1,
            pageCount: 1
        )
    }
}
