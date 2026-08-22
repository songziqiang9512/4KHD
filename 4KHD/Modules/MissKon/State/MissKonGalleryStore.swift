import Foundation
import Observation

@MainActor
@Observable
final class MissKonGalleryStore {
    let feed: MissKonFeedStore
    let detail: MissKonDetailStore
    let favorites: FavoritesStore

    init(feed: MissKonFeedStore, detail: MissKonDetailStore, favorites: FavoritesStore) {
        self.feed = feed
        self.detail = detail
        self.favorites = favorites
        // Wire feed selection changes to detail preparation.
        // 选中即解析首页:MediaFire 等元信息不依赖详情面板打开即可用;
        // 首页已缓存时 resolve 不产生网络请求。
        feed.onSelectionChanged = { [weak detail] item in
            if let item {
                detail?.prepare(item: item)
                detail?.resolve(item: item)
            } else {
                detail?.clear()
            }
        }
        if let item = feed.selectedItem {
            detail.prepare(item: item)
            detail.resolve(item: item)
        } else {
            detail.clear()
        }
    }

    var section: MissKonSection {
        get { feed.section }
        set { feed.section = newValue }
    }

    var visibleItems: [MissKonItem] { feed.visibleItems }
    var allItems: [MissKonItem] { feed.allItems }
    var selectedItemID: MissKonItem.ID? {
        get { feed.selectedItemID }
        set {
            feed.selectedItemID = newValue
            if let item = feed.selectedItem {
                detail.prepare(item: item)
                detail.resolve(item: item)
            } else {
                detail.clear()
            }
        }
    }
    var isRefreshingList: Bool { feed.isRefreshingList }
    var canLoadMoreList: Bool { feed.canLoadMoreList }
    var feedErrorMessage: String? { feed.feedErrorMessage }
    var searchText: String { feed.searchText }
    var activeSearchQuery: String? { feed.activeSearchQuery }

    var imageSlots: [MissKonImageSlot] { detail.imageSlots }
    var selectedSlotID: MissKonImageSlot.ID? {
        get { detail.selectedSlotID }
        set {
            if let newValue {
                detail.selectSlot(id: newValue)
            }
        }
    }
    var isResolving: Bool { detail.isResolving }
    var errorMessage: String? { detail.errorMessage }
    var currentItem: MissKonItem? { detail.currentItem }
    var resolvedPageCount: Int { detail.resolvedPageCount }
    var resolvedImageCount: Int { detail.resolvedImageCount }

    func select(_ item: MissKonItem) {
        feed.select(item)
    }

    func refreshFromNetwork() { feed.refreshFromNetwork() }
    func retryLastFailure() { feed.retryLastFailure() }
    func bootstrapIfNeeded() { feed.bootstrapIfNeeded() }
    func loadMoreListIfNeeded() { feed.loadMoreListIfNeeded() }
    func setSearchText(_ text: String) { feed.setSearchText(text) }
    func submitSearch(_ query: String) { feed.submitSearch(query) }
    func clearSearch() { feed.clearSearch() }

    // MARK: - Favorites

    func isFavorite(_ item: MissKonItem) -> Bool {
        favorites.contains(detailURL: item.detailURL)
    }

    func toggleFavorite(for item: MissKonItem) async throws {
        try await favorites.toggle(MissKonFavoritesBridge.record(from: item))
    }
}
