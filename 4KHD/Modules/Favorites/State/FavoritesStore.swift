import Foundation

/// 收藏列表 + 持久化。
/// 这里只管理收藏记录本身，不承载具体业务模块的展示模型。
@MainActor
@Observable
final class FavoritesStore {
    struct BackupFile: Codable {
        let formatVersion: Int
        let exportedAt: Date
        let favorites: [FavoriteRecord]
    }

    struct ImportResult {
        let addedCount: Int
        let updatedCount: Int
        let skippedCount: Int

        var importedCount: Int { addedCount + updatedCount }
    }

    private(set) var favorites: [FavoriteRecord] = []

    @ObservationIgnored private static let defaultsKey = "com.songziqiang.4khd.favoriteItems.v1"

    init() {
        load()
    }

    func contains(detailURL: URL) -> Bool {
        favorites.contains { $0.detailURL == detailURL.absoluteString }
    }

    /// 切换收藏状态。返回切换后的最新值；同步更新 `DetailPageImageCache` 的 `isPersistent`，
    /// 让收藏的画廊缓存不被 7 天过期清掉。
    @discardableResult
    func toggle(_ record: FavoriteRecord) -> Bool {
        guard let detailURL = URL(string: record.detailURL) else { return false }
        if let index = favorites.firstIndex(where: { $0.detailURL == record.detailURL }) {
            favorites.remove(at: index)
            DetailPageImageCache.shared.setPersistent(false, forDetailURL: detailURL)
            save()
            return false
        }
        favorites.append(record)
        DetailPageImageCache.shared.setPersistent(true, forDetailURL: detailURL)
        save()
        return true
    }

    func exportFavorites(to fileURL: URL) throws {
        let backup = BackupFile(
            formatVersion: 1,
            exportedAt: Date(),
            favorites: favorites
        )
        let data = try Self.jsonEncoder.encode(backup)
        try data.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    func importFavorites(from fileURL: URL) throws -> ImportResult {
        let data = try Data(contentsOf: fileURL)
        let importedFavorites = try Self.decodeBackupFavorites(from: data)

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

        favorites = orderedDetailURLs.compactMap { mergedByDetailURL[$0] }
        save()
        markFavoriteCachesPersistent()
        DetailPageImageCache.shared.prune()

        return ImportResult(
            addedCount: addedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount
        )
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteRecord].self, from: data) else {
            favorites = []
            return
        }
        favorites = decoded
        markFavoriteCachesPersistent()
        DetailPageImageCache.shared.prune()
    }

    private func markFavoriteCachesPersistent() {
        // 把已收藏画廊的 detail cache 都标为 persistent。
        for favorite in favorites {
            if let detailURL = URL(string: favorite.detailURL) {
                DetailPageImageCache.shared.setPersistent(true, forDetailURL: detailURL)
            }
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func decodeBackupFavorites(from data: Data) throws -> [FavoriteRecord] {
        if let backup = try? jsonDecoder.decode(BackupFile.self, from: data) {
            return backup.favorites
        }
        return try jsonDecoder.decode([FavoriteRecord].self, from: data)
    }

    private static func isValidFavorite(_ favorite: FavoriteRecord) -> Bool {
        !favorite.id.isEmpty
            && !favorite.sourceID.isEmpty
            && URL(string: favorite.detailURL) != nil
    }
}
