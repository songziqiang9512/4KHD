import Foundation

/// 收藏列表 + 持久化。
/// 这里只管理收藏记录本身，不承载具体业务模块的展示模型。
@MainActor
@Observable
final class FavoritesStore {
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

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteRecord].self, from: data) else {
            favorites = []
            return
        }
        favorites = decoded
        // 把已收藏画廊的 detail cache 都标为 persistent。
        for favorite in favorites {
            if let detailURL = URL(string: favorite.detailURL) {
                DetailPageImageCache.shared.setPersistent(true, forDetailURL: detailURL)
            }
        }
        DetailPageImageCache.shared.prune()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
