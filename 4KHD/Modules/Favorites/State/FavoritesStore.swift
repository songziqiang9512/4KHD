import Foundation
import OSLog

enum FavoritesStoreError: LocalizedError, Equatable {
    case storageUnavailable
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "无法访问收藏存储位置"
        case .persistenceFailed:
            "收藏写入失败，请检查磁盘空间和文件权限"
        }
    }
}

private struct FavoritesStorageSnapshot: Sendable {
    let favorites: [FavoriteRecord]
    let revision: Int
    let didMigrateLegacyData: Bool
}

private struct FavoritesStorageImportResult: Sendable {
    let snapshot: FavoritesStorageSnapshot
    let addedCount: Int
    let updatedCount: Int
    let skippedCount: Int
}

/// Owns the authoritative snapshot and all file mutations. Methods intentionally
/// perform synchronous file IO on this actor so a transaction never yields
/// between reading the current snapshot and atomically publishing its successor.
private actor FavoritesStorageCoordinator {
    private static let backupFileName = "favorites.json.bak"

    private let fileURL: URL?
    private var favorites: [FavoriteRecord] = []
    private var revision = 0

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    func bootstrap(legacyData: Data?) -> FavoritesStorageSnapshot {
        load(legacyData: legacyData)
    }

    func reload(legacyData: Data?) -> FavoritesStorageSnapshot {
        load(legacyData: legacyData)
    }

    func currentSnapshot() -> FavoritesStorageSnapshot {
        snapshot(didMigrateLegacyData: false)
    }

    func toggle(_ record: FavoriteRecord) throws -> (snapshot: FavoritesStorageSnapshot, isFavorite: Bool) {
        var updated = favorites
        let isFavorite: Bool
        if let index = updated.firstIndex(where: { $0.detailURL == record.detailURL }) {
            updated.remove(at: index)
            isFavorite = false
        } else {
            updated.insert(record, at: 0)
            isFavorite = true
        }
        try commit(updated)
        return (snapshot(didMigrateLegacyData: false), isFavorite)
    }

    func importRecords(_ imported: [FavoriteRecord]) throws -> FavoritesStorageImportResult {
        let existingIndex = Self.stableIndex(favorites)
        var mergedByDetailURL = existingIndex.recordsByDetailURL
        var orderedDetailURLs = existingIndex.orderedDetailURLs
        var addedCount = 0
        var updatedCount = 0
        var skippedCount = 0

        for candidate in imported {
            guard let favorite = Self.sanitizedImportedFavorite(candidate) else {
                skippedCount += 1
                continue
            }
            if mergedByDetailURL[favorite.detailURL] == nil {
                orderedDetailURLs.append(favorite.detailURL)
                addedCount += 1
            } else {
                updatedCount += 1
            }
            mergedByDetailURL[favorite.detailURL] = favorite
        }

        try commit(orderedDetailURLs.compactMap { mergedByDetailURL[$0] })
        return FavoritesStorageImportResult(
            snapshot: snapshot(didMigrateLegacyData: false),
            addedCount: addedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount
        )
    }

    func removeAll() throws -> FavoritesStorageSnapshot {
        try commit([])
        return snapshot(didMigrateLegacyData: false)
    }

    private func load(legacyData: Data?) -> FavoritesStorageSnapshot {
        let fileFavorites = fileURL.flatMap(Self.readFavorites)
        let backupFavorites = fileURL.flatMap { Self.readFavorites($0.deletingLastPathComponent().appendingPathComponent(Self.backupFileName)) }
        let legacyFavorites = legacyData.flatMap { try? JSONDecoder().decode([FavoriteRecord].self, from: $0) }
        var didMigrateLegacyData = false

        if let legacyFavorites {
            favorites = Self.merge(fileFavorites ?? backupFavorites ?? [], legacyFavorites)
            if let fileURL {
                do {
                    try Self.write(favorites, to: fileURL)
                    didMigrateLegacyData = true
                } catch {
                    didMigrateLegacyData = false
                }
            }
        } else {
            favorites = fileFavorites ?? backupFavorites ?? []
            if fileFavorites == nil, let fileURL, !favorites.isEmpty {
                try? Self.write(favorites, to: fileURL)
            }
        }
        revision += 1
        return snapshot(didMigrateLegacyData: didMigrateLegacyData)
    }

    private func commit(_ updated: [FavoriteRecord]) throws {
        guard let fileURL else { throw FavoritesStoreError.storageUnavailable }
        do {
            try Self.write(updated, to: fileURL)
        } catch {
            os_log(.error, "FavoritesStore: save failed: \(error.localizedDescription)")
            throw FavoritesStoreError.persistenceFailed
        }
        favorites = updated
        revision += 1
    }

    private func snapshot(didMigrateLegacyData: Bool) -> FavoritesStorageSnapshot {
        FavoritesStorageSnapshot(
            favorites: favorites,
            revision: revision,
            didMigrateLegacyData: didMigrateLegacyData
        )
    }

    private static func readFavorites(_ fileURL: URL) -> [FavoriteRecord]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([FavoriteRecord].self, from: data)
    }

    private static func merge(_ primary: [FavoriteRecord], _ secondary: [FavoriteRecord]) -> [FavoriteRecord] {
        let primaryIndex = stableIndex(primary)
        var mergedByDetailURL = primaryIndex.recordsByDetailURL
        var orderedDetailURLs = primaryIndex.orderedDetailURLs
        let primaryDetailURLs = Set(primaryIndex.orderedDetailURLs)

        // The file snapshot remains authoritative over legacy UserDefaults.
        // Within either input, the first occurrence owns the stable position
        // while a later duplicate supplies the record contents.
        for favorite in secondary where !primaryDetailURLs.contains(favorite.detailURL) {
            if mergedByDetailURL[favorite.detailURL] == nil {
                orderedDetailURLs.append(favorite.detailURL)
            }
            mergedByDetailURL[favorite.detailURL] = favorite
        }
        return orderedDetailURLs.compactMap { mergedByDetailURL[$0] }
    }

    private static func stableIndex(
        _ records: [FavoriteRecord]
    ) -> (recordsByDetailURL: [String: FavoriteRecord], orderedDetailURLs: [String]) {
        var recordsByDetailURL: [String: FavoriteRecord] = [:]
        var orderedDetailURLs: [String] = []
        for favorite in records {
            if recordsByDetailURL[favorite.detailURL] == nil {
                orderedDetailURLs.append(favorite.detailURL)
            }
            recordsByDetailURL[favorite.detailURL] = favorite
        }
        return (recordsByDetailURL, orderedDetailURLs)
    }

    private static func write(_ snapshot: [FavoriteRecord], to fileURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let nextData = try JSONEncoder().encode(snapshot)
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent(backupFileName)

        // Preserve only a decodable last-known-good main file. Backup update
        // happens before the atomic main replacement; if either step fails the
        // in-memory snapshot remains unchanged.
        if let currentData = try? Data(contentsOf: fileURL),
           (try? JSONDecoder().decode([FavoriteRecord].self, from: currentData)) != nil {
            try currentData.write(to: backupURL, options: .atomic)
        }
        try nextData.write(to: fileURL, options: .atomic)
    }

    private static func isValidFavorite(_ favorite: FavoriteRecord) -> Bool {
        !favorite.id.isEmpty
            && !favorite.sourceID.isEmpty
            && FavoriteSource.source(for: favorite) != nil
    }

    /// Backup files are external input. Keep a valid record even when its
    /// optional cover is stale, but never persist a cover owned by another
    /// source (or an insecure/lookalike host) into the authoritative snapshot.
    private static func sanitizedImportedFavorite(_ favorite: FavoriteRecord) -> FavoriteRecord? {
        guard isValidFavorite(favorite),
              let source = FavoriteSource.source(for: favorite) else { return nil }
        guard favorite.coverURL != nil,
              source.validatedCoverURL(for: favorite) == nil else { return favorite }
        return FavoriteRecord(
            id: favorite.id,
            sourceID: favorite.sourceID,
            title: favorite.title,
            rawTitle: favorite.rawTitle,
            subtitle: favorite.subtitle,
            detailURL: favorite.detailURL,
            coverURL: nil,
            imageCount: favorite.imageCount,
            pageCount: favorite.pageCount
        )
    }
}

/// 收藏列表 + 持久化。
/// 这里只管理收藏记录本身，不承载具体业务模块的展示模型。
@MainActor
@Observable
final class FavoritesStore {
    nonisolated struct BackupFile: Codable, Sendable {
        let formatVersion: Int
        let exportedAt: Date
        let favorites: [FavoriteRecord]
    }

    struct ImportResult: Sendable {
        let addedCount: Int
        let updatedCount: Int
        let skippedCount: Int

        var importedCount: Int { addedCount + updatedCount }
    }

    private(set) var favorites: [FavoriteRecord] = []
    private(set) var isLoaded = false
    /// favorites 每次变更自增,供派生缓存(FavoritesModuleStore.visibleRecords)识别失效。
    private(set) var favoritesRevision = 0
    /// detailURL 集合索引:contains 查询 O(1),与 favorites 同步维护。
    @ObservationIgnored private var favoriteDetailURLs = Set<String>()

    @ObservationIgnored private static let defaultsKey = "com.songziqiang.4khd.favoriteItems.v1"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storage: FavoritesStorageCoordinator
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var appliedStorageRevision = 0

    /// File-based storage in Application Support — Apple recommends against
    /// storing large collections in UserDefaults.
    @ObservationIgnored private static var defaultFavoritesFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir
            .appendingPathComponent("4KHD", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        let resolvedFileURL = fileURL ?? Self.defaultFavoritesFileURL
        self.defaults = defaults
        storage = FavoritesStorageCoordinator(fileURL: resolvedFileURL)
        let legacyData = defaults.data(forKey: Self.defaultsKey)
        loadTask = Task { [weak self] in
            guard let self else { return }
            let result = await storage.bootstrap(legacyData: legacyData)
            guard !Task.isCancelled else { return }
            apply(result)
            isLoaded = true
            if result.didMigrateLegacyData {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
            loadTask = nil
        }
    }

    /// 读 revision 建立观察依赖：favoriteDetailURLs 是 @ObservationIgnored 性能索引，
    /// 直接读它不会被 Observation 追踪，收藏切换后依赖 isFavorite 的 UI
    /// （工具栏收藏按钮、网格 badge）收不到变更通知，只能等下一次手动刷新。
    /// revision 在 favorites 每次变更（加载/toggle/导入）时自增。
    func contains(detailURL: URL) -> Bool {
        _ = favoritesRevision
        return favoriteDetailURLs.contains(detailURL.absoluteString)
    }

    /// 切换收藏状态。返回切换后的最新值；同步更新 `DetailPageImageCache` 的 `isPersistent`，
    /// 让收藏的画廊缓存不被 7 天过期清掉。
    @discardableResult
    func toggle(_ record: FavoriteRecord) async throws -> Bool {
        await waitUntilLoaded()
        guard URL(string: record.detailURL) != nil else { return false }
        let result = try await storage.toggle(record)
        apply(result.snapshot)
        return result.isFavorite
    }

    func exportFavorites(to fileURL: URL) async throws {
        await waitUntilLoaded()
        let current = await storage.currentSnapshot().favorites
        let backup = BackupFile(
            formatVersion: 1,
            exportedAt: Date(),
            favorites: current
        )
        try await Task.detached(priority: .utility) {
            let data = try Self.makeJSONEncoder().encode(backup)
            try data.write(to: fileURL, options: .atomic)
        }.value
    }

    @discardableResult
    func importFavorites(from fileURL: URL) async throws -> ImportResult {
        await waitUntilLoaded()
        let importedFavorites = try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: fileURL)
            return try Self.decodeBackupFavorites(from: data)
        }.value

        let result = try await storage.importRecords(importedFavorites)
        apply(result.snapshot)

        return ImportResult(
            addedCount: result.addedCount,
            updatedCount: result.updatedCount,
            skippedCount: result.skippedCount
        )
    }

    func removeAllFavorites() async throws {
        await waitUntilLoaded()
        apply(try await storage.removeAll())
    }

    // MARK: - 持久化

    func waitUntilLoaded() async {
        if let loadTask {
            await loadTask.value
        }
    }

    /// Re-reads the persisted snapshot so a favorites section opened after an
    /// app replacement can discover data written by the previous process.
    func reloadFromDisk() async {
        await waitUntilLoaded()
        let legacyData = defaults.data(forKey: Self.defaultsKey)
        let result = await storage.reload(legacyData: legacyData)
        guard !Task.isCancelled else { return }
        apply(result)
        isLoaded = true
        if result.didMigrateLegacyData {
            defaults.removeObject(forKey: Self.defaultsKey)
        }
    }

    private func apply(_ snapshot: FavoritesStorageSnapshot) {
        guard snapshot.revision > appliedStorageRevision else { return }
        appliedStorageRevision = snapshot.revision
        let previousURLs = favoriteDetailURLs
        let nextURLs = Set(snapshot.favorites.map(\.detailURL))
        favorites = snapshot.favorites
        favoriteDetailURLs = nextURLs
        favoritesRevision += 1

        for removedURL in previousURLs.subtracting(nextURLs).compactMap(URL.init(string:)) {
            DetailPageImageCache.shared.setPersistent(false, forDetailURL: removedURL)
        }
        for addedURL in nextURLs.subtracting(previousURLs).compactMap(URL.init(string:)) {
            DetailPageImageCache.shared.setPersistent(true, forDetailURL: addedURL)
        }
        DetailPageImageCache.shared.prune()
    }

    private nonisolated static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private nonisolated static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private nonisolated static func decodeBackupFavorites(from data: Data) throws -> [FavoriteRecord] {
        if let backup = try? makeJSONDecoder().decode(BackupFile.self, from: data) {
            return backup.favorites
        }
        return try makeJSONDecoder().decode([FavoriteRecord].self, from: data)
    }

}
