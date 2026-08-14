@testable import _KHD
import XCTest

final class FavoritesModuleStoreTests: XCTestCase {
    // MARK: - 来源判定

    @MainActor
    func testSourceDeterminationByHost() {
        XCTAssertEqual(FavoriteSource.source(for: Self.makeRecord(id: "g1", detailURL: "https://www.4khd.com/content/a.html")), .gallery)
        XCTAssertEqual(FavoriteSource.source(for: Self.makeRecord(id: "g2", detailURL: "https://img.4khd.com/pic/x.jpg")), .gallery)
        XCTAssertEqual(FavoriteSource.source(for: Self.makeRecord(id: "m1", detailURL: "https://misskon.com/xxx/")), .missKon)
        XCTAssertEqual(FavoriteSource.source(for: Self.makeRecord(id: "m2", detailURL: "https://www.misskon.com/tag/y/")), .missKon)
        XCTAssertEqual(FavoriteSource.source(for: Self.makeRecord(id: "w1", detailURL: "https://wallhaven.cc/w/123")), .wallhaven)
        XCTAssertEqual(FavoriteSource.source(for: Self.makeRecord(id: "w2", detailURL: "https://whvn.cc/w/456")), .wallhaven)
        XCTAssertNil(FavoriteSource.source(for: Self.makeRecord(id: "u1", detailURL: "https://example.com/foo")))
        XCTAssertNil(FavoriteSource.source(for: Self.makeRecord(id: "u2", detailURL: "not a url")))
    }

    // MARK: - 筛选 / 顺序 / 未知来源剔除

    @MainActor
    func testVisibleRecordsPreservesStoreOrderAndFiltersBySource() async throws {
        let (_, moduleStore) = try await makeLoadedStores(records: [
            Self.makeRecord(id: "g1", detailURL: "https://www.4khd.com/content/a.html"),
            Self.makeRecord(id: "m1", detailURL: "https://misskon.com/xxx/"),
            Self.makeRecord(id: "w1", detailURL: "https://wallhaven.cc/w/123"),
            Self.makeRecord(id: "u1", detailURL: "https://example.com/foo"),
            Self.makeRecord(id: "g2", detailURL: "https://www.4khd.com/content/b.html"),
        ])

        // 全部:保持原始顺序,剔除未知来源。
        moduleStore.filter = .all
        XCTAssertEqual(moduleStore.visibleRecords.map(\.id), ["g1", "m1", "w1", "g2"])

        moduleStore.filter = .gallery
        XCTAssertEqual(moduleStore.visibleRecords.map(\.id), ["g1", "g2"])

        moduleStore.filter = .missKon
        XCTAssertEqual(moduleStore.visibleRecords.map(\.id), ["m1"])

        moduleStore.filter = .wallhaven
        XCTAssertEqual(moduleStore.visibleRecords.map(\.id), ["w1"])
    }

    // MARK: - 搜索过滤

    @MainActor
    func testSearchFiltersByTitleAndClears() async throws {
        let (_, moduleStore) = try await makeLoadedStores(records: [
            Self.makeRecord(id: "g1", detailURL: "https://www.4khd.com/content/a.html", title: "Sunset Vol 1"),
            Self.makeRecord(id: "m1", detailURL: "https://misskon.com/xxx/", title: "Beach Day"),
            Self.makeRecord(id: "w1", detailURL: "https://wallhaven.cc/w/123", title: "Sunset Wallpaper")
        ])

        moduleStore.searchText = "sunset"
        moduleStore.submitSearch()
        XCTAssertEqual(moduleStore.visibleRecords.map(\.id), ["g1", "w1"])
        XCTAssertEqual(moduleStore.activeSearchQuery, "sunset")

        moduleStore.clearSearch()
        XCTAssertNil(moduleStore.activeSearchQuery)
        XCTAssertEqual(moduleStore.visibleRecords.map(\.id), ["g1", "m1", "w1"])
    }

    // MARK: - 选中同步

    @MainActor
    func testSelectionSyncAndFollowsFavoritesMutation() async throws {
        let (favoritesStore, moduleStore) = try await makeLoadedStores(records: [
            Self.makeRecord(id: "g1", detailURL: "https://www.4khd.com/content/a.html"),
            Self.makeRecord(id: "m1", detailURL: "https://misskon.com/xxx/"),
        ])

        XCTAssertNil(moduleStore.selectedRecord)

        guard let first = moduleStore.visibleRecords.first else {
            return XCTFail("visibleRecords 不应为空")
        }
        moduleStore.select(record: first)
        XCTAssertEqual(moduleStore.selectedRecordID, "g1")
        XCTAssertEqual(moduleStore.selectedRecord?.id, "g1")

        // 收藏被取消(其它模块路径 toggle)后,选中记录随之消失。
        try await favoritesStore.toggle(first)
        XCTAssertNil(moduleStore.selectedRecord)
        XCTAssertEqual(moduleStore.visibleRecords.map(\.id), ["m1"])

        // 选中过滤后不可见的记录时,selectedRecord 为空。
        moduleStore.select(record: moduleStore.visibleRecords.first)
        moduleStore.filter = .gallery
        XCTAssertNil(moduleStore.selectedRecord)
    }

    // MARK: - 辅助

    @MainActor
    private func makeLoadedStores(
        records: [FavoriteRecord]
    ) async throws -> (FavoritesStore, FavoritesModuleStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("favorites.json")
        try JSONEncoder().encode(records).write(to: fileURL)
        let favoritesStore = FavoritesStore(fileURL: fileURL)
        await favoritesStore.waitUntilLoaded()
        return (favoritesStore, FavoritesModuleStore(favoritesStore: favoritesStore))
    }

    private static func makeRecord(id: String, detailURL: String, title: String? = nil) -> FavoriteRecord {
        FavoriteRecord(
            id: id,
            sourceID: "legacy",
            title: title ?? "Title \(id)",
            rawTitle: title ?? "Title \(id)",
            subtitle: "",
            detailURL: detailURL,
            coverURL: nil,
            imageCount: 1,
            pageCount: 1
        )
    }
}
