import Foundation
import Observation

@MainActor
@Observable
final class WallhavenGalleryStore {
    let feed: WallhavenFeedStore
    let favorites: FavoritesStore

    init(feed: WallhavenFeedStore, favorites: FavoritesStore) {
        self.feed = feed
        self.favorites = favorites

        feed.onSelectionChanged = { [weak self] wallpaper in
            self?.selectedWallpaper = wallpaper
        }
        if let wallpaper = feed.selectedWallpaper {
            selectedWallpaper = wallpaper
        }
    }

    // MARK: - Convenience accessors

    var section: WallhavenSection { feed.section }

    func setSection(_ section: WallhavenSection) { feed.setSection(section) }
    var wallpapers: [Wallpaper] { feed.wallpapers }
    var selectedWallpaperID: Wallpaper.ID? {
        get { feed.selectedWallpaperID }
        set {
            feed.selectedWallpaperID = newValue
            selectedWallpaper = feed.selectedWallpaper
        }
    }
    var isRefreshingList: Bool { feed.isRefreshingList }
    var canLoadMoreList: Bool { feed.canLoadMoreList }
    var feedErrorMessage: String? { feed.feedErrorMessage }
    var searchText: String { feed.searchText }
    var activeSearchQuery: String? { feed.activeSearchQuery }

    var category: WallhavenCategory { feed.category }
    var sorting: WallhavenSorting { feed.sorting }
    var purity: WallhavenPurity { feed.purity }
    var hasAPIKey: Bool { feed.hasAPIKey }
    var allowedPurities: [WallhavenPurity] { feed.allowedPurities }
    var resolvedWallpaper: Wallpaper? { feed.resolvedWallpaper }
    var isResolvingDetail: Bool { feed.isResolvingDetail }
    var resolution: WallhavenResolution { feed.resolution }
    var ratio: WallhavenRatio { feed.ratio }

    var selectedWallpaper: Wallpaper?

    /// Best available wallpaper data — resolved detail wins over search data.
    var effectiveSelectedWallpaper: Wallpaper? {
        if let resolved = feed.resolvedWallpaper, resolved.id == selectedWallpaper?.id {
            return resolved
        }
        return selectedWallpaper
    }

    func select(_ wallpaper: Wallpaper) { feed.select(wallpaper) }
    func refreshFromNetwork() { feed.refreshFromNetwork() }
    func retryLastFailure() { feed.retryLastFailure() }
    func bootstrapIfNeeded() { feed.bootstrapIfNeeded() }
    func loadMoreIfNeeded() { feed.loadMoreIfNeeded() }
    func setSearchText(_ text: String) { feed.setSearchText(text) }
    func submitSearch(_ query: String) { feed.submitSearch(query) }
    func clearSearch() { feed.clearSearch() }

    func setCategory(_ newValue: WallhavenCategory) { feed.setCategory(newValue) }
    func setSorting(_ newValue: WallhavenSorting) { feed.setSorting(newValue) }
    func setResolution(_ newValue: WallhavenResolution) { feed.setResolution(newValue) }
    func setRatio(_ newValue: WallhavenRatio) { feed.setRatio(newValue) }
    func setPurity(_ newValue: WallhavenPurity) { feed.setPurity(newValue) }

    func resolveDetail(for wallpaper: Wallpaper) { feed.resolveDetail(for: wallpaper) }
    func cancelResolveDetail() { feed.cancelResolveDetail() }

    var isBrowsingUploader: Bool { feed.isBrowsingUploader }
    func showUploaderWorks(username: String) { feed.showUploaderWorks(username: username) }
    func restorePreviousBrowseState() { feed.restorePreviousBrowseState() }

    // MARK: - Favorites

    func isFavorite(_ wallpaper: Wallpaper) -> Bool {
        favorites.contains(detailURL: wallpaper.sourcePageUrl)
    }

    func toggleFavorite(for wallpaper: Wallpaper) async throws {
        try await favorites.toggle(WallhavenFavoritesBridge.record(from: wallpaper))
    }
}
