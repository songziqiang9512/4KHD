import Foundation

/// 工作区门面：组合 feed / detail / favorites 三个子 store，给现有 view 一个统一入口。
/// 长期来看 view 可以直接注入需要的子 store 减少耦合；目前先保持原 view API 不变。
@MainActor
@Observable
final class LibraryStore {
    let feed: GalleryFeedStore
    let detail: GalleryDetailStore
    let favorites: FavoritesStore

    init() {
        let favorites = FavoritesStore()
        let feed = GalleryFeedStore(favoritesStore: favorites)
        let detail = GalleryDetailStore()
        self.favorites = favorites
        self.feed = feed
        self.detail = detail

        // Feed 选中变化时，让 detail 重建 slot —— 取当前 selectedItem 真正的对象（item 可能被 refresh 替换了 pageURLs）。
        feed.onSelectionChanged = { [weak feed, weak detail] in
            detail?.prepare(for: feed?.selectedItem)
        }

        // 启动时 detail 先跟上一次 feed 选中的（init 阶段就有 .latest section 的初始空选择）。
        detail.prepare(for: feed.selectedItem)
        feed.selectFirstItemIfNeeded(force: true)
    }

    // MARK: - Feed 转发

    var section: GallerySection {
        get { feed.section }
        set { feed.section = newValue }
    }

    var selectedItemID: GalleryItem.ID? {
        get { feed.selectedItemID }
        set {
            feed.selectedItemID = newValue
            detail.prepare(for: feed.selectedItem)
        }
    }

    var searchText: String {
        get { feed.searchText }
        set { feed.searchText = newValue }
    }

    var activeSearchQuery: String? { feed.activeSearchQuery }
    var visibleCount: Int { feed.visibleCount }
    var isRefreshingList: Bool { feed.isRefreshingList }
    var allItems: [GalleryItem] { feed.allItems }
    var visibleItems: [GalleryItem] { feed.visibleItems }
    var canLoadMoreList: Bool { feed.canLoadMoreList }
    var selectedItem: GalleryItem? { feed.selectedItem }

    func loadMoreListIfNeeded() { feed.loadMoreListIfNeeded() }
    func submitSearch() { feed.submitSearch() }
    func clearSearch() { feed.clearSearch() }
    func refreshFromNetwork() { feed.refreshFromNetwork() }

    func select(_ item: GalleryItem, force: Bool = false) {
        feed.select(item, force: force)
    }

    // MARK: - Detail 转发

    var selectedImageIndex: Int {
        get { detail.selectedImageIndex }
        set { detail.selectedImageIndex = newValue }
    }

    var loadedImageSlots: [ImageSlot] { detail.loadedImageSlots }
    var prefetchPageURL: URL? { detail.prefetchPageURL }
    var selectedSlot: ImageSlot? { detail.selectedSlot }
    var upcomingKnownImageURLs: [URL] { detail.upcomingKnownImageURLs }

    var isFullscreenViewerPresented: Bool {
        get { detail.isFullscreenViewerPresented }
        set { detail.isFullscreenViewerPresented = newValue }
    }

    func selectImage(at index: Int) { detail.selectImage(at: index) }
    func stepImage(_ delta: Int) { detail.stepImage(delta) }

    @discardableResult
    func ensureNextDetailPageLoaded(reason: DetailPageLoadReason) -> Bool {
        detail.ensureNextDetailPageLoaded(reason: reason)
    }

    func registerResolvedPage(_ page: ResolvedImagePage) {
        if let item = feed.selectedItem, favorites.isFavorite(item) {
            DetailPageImageCache.shared.setPersistent(true, forDetailURL: item.detailURL)
        }
        detail.registerResolvedPage(page)
    }

    // MARK: - Favorites 转发

    func isFavorite(_ item: GalleryItem) -> Bool { favorites.isFavorite(item) }

    func toggleFavorite(for item: GalleryItem) {
        favorites.toggle(for: item)
        if feed.section == .favorites {
            feed.selectFirstItemIfNeeded(force: true)
        }
    }

    func isCached(_ item: GalleryItem) -> Bool {
        DetailPageImageCache.shared.containsCachedPage(forDetailURL: item.detailURL)
    }
}
