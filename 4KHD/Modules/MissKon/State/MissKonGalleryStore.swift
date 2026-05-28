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
        // Wire feed selection changes to detail preparation (no network until detail visible).
        feed.onSelectionChanged = { [weak detail] item in
            if let item {
                detail?.prepare(item: item)
            } else {
                detail?.clear()
            }
        }
        if let item = feed.selectedItem {
            detail.prepare(item: item)
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
        set { detail.selectedSlotID = newValue }
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
    func loadMoreListIfNeeded() { feed.loadMoreListIfNeeded() }
    func setSearchText(_ text: String) { feed.setSearchText(text) }
    func submitSearch(_ query: String) { feed.submitSearch(query) }
    func clearSearch() { feed.clearSearch() }

    // MARK: - Favorites

    func isFavorite(_ item: MissKonItem) -> Bool {
        favorites.contains(detailURL: item.detailURL)
    }

    func toggleFavorite(for item: MissKonItem) {
        favorites.toggle(MissKonFavoritesBridge.record(from: item))
        if feed.section == .favorites {
            feed.restoreSectionCache()
        }
    }
}
