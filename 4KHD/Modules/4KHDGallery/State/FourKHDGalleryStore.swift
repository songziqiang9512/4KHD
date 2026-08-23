import Foundation

/// 工作区门面：组合 feed / detail / favorites 三个子 store，给现有 view 一个统一入口。
/// 长期来看 view 可以直接注入需要的子 store 减少耦合；目前先保持原 view API 不变。
@MainActor
@Observable
final class FourKHDGalleryStore {
    let feed: GalleryFeedStore
    let detail: GalleryDetailStore
    let favorites: FavoritesStore

    init(favorites: FavoritesStore) {
        let feed = GalleryFeedStore()
        let detail = GalleryDetailStore()
        self.favorites = favorites
        self.feed = feed
        self.detail = detail

        // Feed 选中变化时，让 detail 使用 feed 当时发出的 item 快照重建 slot。
        // 不在这里回读 `feed.selectedItem`，避免列表替换 / 选择修正期间读到回退状态。
        feed.onSelectionChanged = { [weak detail] item in
            detail?.prepare(for: item)
        }

        // 启动时明确选中当前列表第一项。后续网络刷新即便 selectedItemID 不变，
        // feed 也会把替换后的 item 快照发给 detail。
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
    var feedErrorMessage: String? { feed.errorMessage }
    var allItems: [GalleryItem] { feed.allItems }
    var visibleItems: [GalleryItem] { feed.visibleItems }
    var canLoadMoreList: Bool { feed.canLoadMoreList }
    var selectedItem: GalleryItem? { feed.selectedItem }

    func loadMoreListIfNeeded() { feed.loadMoreListIfNeeded() }
    func submitSearch() { feed.submitSearch() }
    func clearSearch() { feed.clearSearch() }
    func refreshFromNetwork() { feed.refreshFromNetwork() }
    func retryLastFailure() { feed.retryLastFailure() }
    func bootstrapIfNeeded() { feed.bootstrapIfNeeded() }

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
    var detailErrorMessage: String? { detail.errorMessage }
    var selectedSlot: ImageSlot? { detail.selectedSlot }
    var upcomingKnownImageURLs: [URL] { detail.upcomingKnownImageURLs }
    var recommendations: [OnlineGalleryRecommendation] { detail.recommendations }
    var detailContentMode: WorkspaceDetailContentMode { detail.contentMode }
    var canStepDetailBackward: Bool { detail.canStepBackward }
    var canStepDetailForward: Bool { detail.canStepForward }

    var isFullscreenViewerPresented: Bool {
        get { detail.isFullscreenViewerPresented }
        set { detail.isFullscreenViewerPresented = newValue }
    }

    func selectImage(at index: Int) { detail.selectImage(at: index) }
    func stepImage(_ delta: Int) { detail.stepImage(delta) }

    func cancelOutstandingDetailPageLoads() {
        detail.cancelOutstandingDetailPageLoads()
    }

    @discardableResult
    func ensureNextDetailPageLoaded(reason: DetailPageLoadReason) -> Bool {
        detail.ensureNextDetailPageLoaded(reason: reason)
    }

    func registerResolvedPage(_ page: ResolvedImagePage) {
        if let item = feed.selectedItem, favorites.contains(detailURL: item.detailURL) {
            DetailPageImageCache.shared.setPersistent(true, forDetailURL: item.detailURL)
        }
        detail.registerResolvedPage(page)
    }

    func openRecommendation(_ recommendation: OnlineGalleryRecommendation) {
        let imageCount = recommendation.imageCount ?? 0
        let pageCount = max(Int(ceil(Double(imageCount) / 20.0)), 1)
        let pageURLs = (1...pageCount).map { pageNumber in
            pageNumber == 1
                ? recommendation.detailURL
                : recommendation.detailURL.appendingPathComponent("\(pageNumber)")
        }
        let item = GalleryItem(
            id: recommendation.detailURL.deletingPathExtension().lastPathComponent,
            section: selectedItem?.section ?? section,
            kind: .recommended,
            title: recommendation.title,
            rawTitle: recommendation.title,
            subtitle: "推荐图集",
            detailURL: recommendation.detailURL,
            coverURL: recommendation.coverURL,
            coverAspectRatio: recommendation.coverAspectRatio,
            imageCount: imageCount,
            pageCount: pageCount,
            pageURLs: pageURLs,
            sampleImageURLs: recommendation.coverURL.map { [$0] } ?? []
        )
        feed.select(item, force: true)
    }

    // MARK: - Favorites 转发

    func isFavorite(_ item: GalleryItem) -> Bool { favorites.contains(detailURL: item.detailURL) }

    func toggleFavorite(for item: GalleryItem) async throws {
        try await favorites.toggle(GalleryFavoritesBridge.record(from: item))
    }

    func isCached(_ item: GalleryItem) -> Bool {
        DetailPageImageCache.shared.containsCachedPage(forDetailURL: item.detailURL)
    }
}
