import Foundation

/// 收藏列表 + 持久化。
/// 独立 store 让收藏逻辑跟 feed / detail 解耦：
/// - GalleryFeedStore 在 `.favorites` section 下读取这里的 `galleryItems`。
/// - 详情面板通过 `LibraryStore` 转发的 `toggle / isFavorite` 接口操作。
@MainActor
@Observable
final class FavoritesStore {
    private(set) var favorites: [FavoriteGalleryItem] = []

    @ObservationIgnored private static let defaultsKey = "com.songziqiang.4khd.favoriteItems.v1"

    init() {
        load()
    }

    var galleryItems: [GalleryItem] {
        favorites.compactMap(Self.toGalleryItem)
    }

    func isFavorite(_ item: GalleryItem) -> Bool {
        favorites.contains { $0.detailURL == item.detailURL.absoluteString }
    }

    /// 切换收藏状态。返回切换后的最新值；同步更新 `DetailPageImageCache` 的 `isPersistent`，
    /// 让收藏的画廊缓存不被 7 天过期清掉。
    @discardableResult
    func toggle(for item: GalleryItem) -> Bool {
        if let index = favorites.firstIndex(where: { $0.detailURL == item.detailURL.absoluteString }) {
            favorites.remove(at: index)
            DetailPageImageCache.shared.setPersistent(false, forDetailURL: item.detailURL)
            save()
            return false
        }
        favorites.append(Self.from(item))
        DetailPageImageCache.shared.setPersistent(true, forDetailURL: item.detailURL)
        save()
        return true
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteGalleryItem].self, from: data) else {
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

    // MARK: - GalleryItem <-> FavoriteGalleryItem

    private static func from(_ item: GalleryItem) -> FavoriteGalleryItem {
        FavoriteGalleryItem(
            id: item.id,
            sectionRawValue: item.section.rawValue,
            title: item.title,
            rawTitle: item.rawTitle,
            subtitle: item.subtitle,
            detailURL: item.detailURL.absoluteString,
            coverURL: item.coverURL?.absoluteString,
            imageCount: item.imageCount,
            pageCount: item.pageCount
        )
    }

    private static func toGalleryItem(_ favorite: FavoriteGalleryItem) -> GalleryItem? {
        guard let section = GallerySection(rawValue: favorite.sectionRawValue),
              section != .favorites,
              let detailURL = URL(string: favorite.detailURL) else {
            return nil
        }
        let coverURL = favorite.coverURL.flatMap(URL.init(string:))
        let pageURLs = Self.pageURLs(detailURL: detailURL, pageCount: favorite.pageCount)
        return GalleryItem(
            id: favorite.id,
            section: section,
            kind: section == .popular ? .recommended : .gallery,
            title: favorite.title,
            rawTitle: favorite.rawTitle,
            subtitle: favorite.subtitle,
            detailURL: detailURL,
            coverURL: coverURL,
            imageCount: favorite.imageCount,
            pageCount: favorite.pageCount,
            pageURLs: pageURLs,
            sampleImageURLs: coverURL.map { [$0] } ?? []
        )
    }

    private static func pageURLs(detailURL: URL, pageCount: Int) -> [URL] {
        let count = max(pageCount, 1)
        return (1...count).map { pageNumber in
            pageNumber == 1 ? detailURL : detailURL.appendingPathComponent("\(pageNumber)")
        }
    }
}
