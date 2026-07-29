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

    private struct LoadResult: Sendable {
        let favorites: [FavoriteRecord]
        let didMigrateLegacyData: Bool
    }

    private(set) var favorites: [FavoriteRecord] = []
    private(set) var isLoaded = false

    @ObservationIgnored private static let defaultsKey = "com.songziqiang.4khd.favoriteItems.v1"
    @ObservationIgnored private let favoritesFileURL: URL?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored var onFavoritesChanged: (() -> Void)? {
        didSet {
            if isLoaded {
                onFavoritesChanged?()
            }
        }
    }

    /// File-based storage in Application Support — Apple recommends against
    /// storing large collections in UserDefaults.
    @ObservationIgnored private static var defaultFavoritesFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return dir
            .appendingPathComponent("4KHD", isDirectory: true)
            .appendingPathComponent("favorites.json")
    }

    init(fileURL: URL? = nil, defaults: UserDefaults = .standard) {
        favoritesFileURL = fileURL ?? Self.defaultFavoritesFileURL
        self.defaults = defaults
        let targetURL = favoritesFileURL
        let legacyData = defaults.data(forKey: Self.defaultsKey)
        loadTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Self.loadSnapshot(fileURL: targetURL, legacyData: legacyData)
            }.value
            guard !Task.isCancelled, let self else { return }
            favorites = result.favorites
            isLoaded = true
            if result.didMigrateLegacyData {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
            loadTask = nil
            markFavoriteCachesPersistent()
            DetailPageImageCache.shared.prune()
            onFavoritesChanged?()
        }
    }

    func contains(detailURL: URL) -> Bool {
        favorites.contains { $0.detailURL == detailURL.absoluteString }
    }

    /// 切换收藏状态。返回切换后的最新值；同步更新 `DetailPageImageCache` 的 `isPersistent`，
    /// 让收藏的画廊缓存不被 7 天过期清掉。
    @discardableResult
    func toggle(_ record: FavoriteRecord) async throws -> Bool {
        await waitUntilLoaded()
        guard let detailURL = URL(string: record.detailURL) else { return false }
        var updatedFavorites = favorites
        let isFavorite: Bool
        if let index = updatedFavorites.firstIndex(where: { $0.detailURL == record.detailURL }) {
            updatedFavorites.remove(at: index)
            isFavorite = false
        } else {
            updatedFavorites.append(record)
            isFavorite = true
        }
        try await persist(updatedFavorites)
        favorites = updatedFavorites
        DetailPageImageCache.shared.setPersistent(isFavorite, forDetailURL: detailURL)
        onFavoritesChanged?()
        return isFavorite
    }

    func exportFavorites(to fileURL: URL) async throws {
        await waitUntilLoaded()
        let backup = BackupFile(
            formatVersion: 1,
            exportedAt: Date(),
            favorites: favorites
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

        var mergedByDetailURL = Dictionary(uniqueKeysWithValues: favorites.map { ($0.detailURL, $0) })
        var orderedDetailURLs = favorites.map(\.detailURL)
        var addedCount = 0
        var updatedCount = 0
        var skippedCount = 0

        for favorite in importedFavorites {
            guard Self.isValidFavorite(favorite) else {
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

        let updatedFavorites = orderedDetailURLs.compactMap { mergedByDetailURL[$0] }
        try await persist(updatedFavorites)
        favorites = updatedFavorites
        markFavoriteCachesPersistent()
        DetailPageImageCache.shared.prune()
        onFavoritesChanged?()

        return ImportResult(
            addedCount: addedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount
        )
    }

    // MARK: - 持久化

    func waitUntilLoaded() async {
        if let loadTask {
            await loadTask.value
        }
    }

    private func markFavoriteCachesPersistent() {
        // 把已收藏画廊的 detail cache 都标为 persistent。
        for favorite in favorites {
            if let detailURL = URL(string: favorite.detailURL) {
                DetailPageImageCache.shared.setPersistent(true, forDetailURL: detailURL)
            }
        }
    }

    private func persist(_ snapshot: [FavoriteRecord]) async throws {
        guard let favoritesFileURL else {
            throw FavoritesStoreError.storageUnavailable
        }
        do {
            try await Task.detached(priority: .utility) {
                try Self.write(snapshot, to: favoritesFileURL)
            }.value
        } catch {
            os_log(.error, "FavoritesStore: save failed: \(error.localizedDescription)")
            throw FavoritesStoreError.persistenceFailed
        }
    }

    private nonisolated static func loadSnapshot(fileURL: URL?, legacyData: Data?) -> LoadResult {
        let fileFavorites: [FavoriteRecord]? = {
            guard let fileURL,
                  let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? JSONDecoder().decode([FavoriteRecord].self, from: data)
        }()
        let legacyFavorites = legacyData.flatMap {
            try? JSONDecoder().decode([FavoriteRecord].self, from: $0)
        }

        guard let legacyFavorites else {
            return LoadResult(favorites: fileFavorites ?? [], didMigrateLegacyData: false)
        }

        let mergedFavorites = mergeFavorites(fileFavorites ?? [], legacyFavorites)
        guard let fileURL else {
            return LoadResult(favorites: mergedFavorites, didMigrateLegacyData: false)
        }
        do {
            try write(mergedFavorites, to: fileURL)
            return LoadResult(favorites: mergedFavorites, didMigrateLegacyData: true)
        } catch {
            return LoadResult(favorites: mergedFavorites, didMigrateLegacyData: false)
        }
    }

    private nonisolated static func mergeFavorites(
        _ primary: [FavoriteRecord],
        _ secondary: [FavoriteRecord]
    ) -> [FavoriteRecord] {
        var mergedByDetailURL = Dictionary(uniqueKeysWithValues: primary.map { ($0.detailURL, $0) })
        var orderedDetailURLs = primary.map(\.detailURL)
        for favorite in secondary {
            guard !mergedByDetailURL.keys.contains(favorite.detailURL) else { continue }
            mergedByDetailURL[favorite.detailURL] = favorite
            orderedDetailURLs.append(favorite.detailURL)
        }
        return orderedDetailURLs.compactMap { mergedByDetailURL[$0] }
    }

    private nonisolated static func write(_ snapshot: [FavoriteRecord], to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomicWrite)
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

    private nonisolated static func isValidFavorite(_ favorite: FavoriteRecord) -> Bool {
        !favorite.id.isEmpty
            && !favorite.sourceID.isEmpty
            && URL(string: favorite.detailURL) != nil
    }
}
