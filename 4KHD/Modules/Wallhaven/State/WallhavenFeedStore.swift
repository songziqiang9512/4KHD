import Foundation
import Observation

@MainActor
@Observable
final class WallhavenFeedStore {
    var section: WallhavenSection = .browse

    var wallpapers: [Wallpaper] = []
    var selectedWallpaperID: Wallpaper.ID?
    var isRefreshingList = false
    var canLoadMoreList = false
    var feedErrorMessage: String?

    var searchText = ""
    var activeSearchQuery: String?

    // Filter state — changes to any filter reset page=1.
    var category: WallhavenCategory
    var sorting: WallhavenSorting
    var resolution: WallhavenResolution
    var ratio: WallhavenRatio

    private var currentPage = 1
    private var lastPage = 1
    private var seed: String?

    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?

    /// Cached per section preserves items across section switches (currently only .browse).
    private var cachedWallpapers: [WallhavenSection: [Wallpaper]] = [:]
    private var cachedPages: [WallhavenSection: (current: Int, last: Int, seed: String?)] = [:]
    private var cacheTimestamps: [WallhavenSection: Date] = [:]

    private static let cacheMaxAge: TimeInterval = 3600

    private let apiClient: WallhavenAPIClient
    let accountStore: WallhavenAccountStore
    private let preferences: WallhavenContentPreferences
    private let favoritesStore: FavoritesStore

    @ObservationIgnored var onSelectionChanged: ((Wallpaper?) -> Void)?

    init(apiClient: WallhavenAPIClient? = nil,
         accountStore: WallhavenAccountStore,
         preferences: WallhavenContentPreferences,
         favoritesStore: FavoritesStore) {
        self.apiClient = apiClient ?? WallhavenAPIClient()
        self.accountStore = accountStore
        self.preferences = preferences
        self.favoritesStore = favoritesStore
        self.category = preferences.preferredCategory
        self.sorting = preferences.preferredSorting
        self.resolution = preferences.preferredResolution
        self.ratio = preferences.preferredRatio
    }

    /// The effective purity for API requests, from AccountStore.
    var purity: WallhavenPurity {
        accountStore.purity
    }

    /// Whether API key is configured (controls purity availability).
    var hasAPIKey: Bool {
        accountStore.hasAPIKey
    }

    /// Purity values the user is allowed to select.
    var allowedPurities: [WallhavenPurity] {
        accountStore.allowedPurities
    }

    func setPurity(_ newValue: WallhavenPurity) {
        guard accountStore.allowedPurities.contains(newValue) else { return }
        guard accountStore.purity != newValue else { return }
        accountStore.purity = newValue
        resetAndRefresh()
    }

    var selectedWallpaper: Wallpaper? {
        guard let selectedWallpaperID else { return nil }
        return wallpapers.first { $0.id == selectedWallpaperID }
    }

    func select(_ wallpaper: Wallpaper) {
        guard selectedWallpaperID != wallpaper.id else { return }
        selectedWallpaperID = wallpaper.id
        onSelectionChanged?(wallpaper)
    }

    // MARK: - Filter change

    func setCategory(_ newValue: WallhavenCategory) {
        guard category != newValue else { return }
        category = newValue
        preferences.preferredCategory = newValue
        resetAndRefresh()
    }

    func setSorting(_ newValue: WallhavenSorting) {
        guard sorting != newValue else { return }
        sorting = newValue
        preferences.preferredSorting = newValue
        resetAndRefresh()
    }

    func setResolution(_ newValue: WallhavenResolution) {
        guard resolution != newValue else { return }
        resolution = newValue
        preferences.preferredResolution = newValue
        resetAndRefresh()
    }

    func setRatio(_ newValue: WallhavenRatio) {
        guard ratio != newValue else { return }
        ratio = newValue
        preferences.preferredRatio = newValue
        resetAndRefresh()
    }

    private func resetAndRefresh() {
        loadTask?.cancel()
        loadTask = nil
        searchTask?.cancel()
        searchTask = nil
        activeSearchQuery = nil
        searchText = ""
        cachedWallpapers[section] = nil
        cachedPages[section] = nil
        cacheTimestamps[section] = nil
        wallpapers = []
        currentPage = 1
        lastPage = 1
        seed = nil
        canLoadMoreList = false
        isRefreshingList = false
        feedErrorMessage = nil
        refreshFromNetwork()
    }

    // MARK: - Network

    func setSection(_ newSection: WallhavenSection) {
        guard section != newSection else { return }
        loadTask?.cancel()
        searchTask?.cancel()
        activeSearchQuery = nil
        searchText = ""
        section = newSection
        restoreSectionCache()
    }

    func refreshFromNetwork() {
        if section == .favorites {
            refreshFavorites()
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            let searchSection = self.section
            do {
                let page = try await self.performSearch(page: 1)
                guard !Task.isCancelled else { return }
                self.cachedWallpapers[searchSection] = page.wallpapers
                self.cachedPages[searchSection] = (page.currentPage, page.lastPage, page.seed)
                self.cacheTimestamps[searchSection] = Date()
                if self.section == searchSection, self.activeSearchQuery == nil {
                    self.wallpapers = page.wallpapers
                    self.currentPage = page.currentPage
                    self.lastPage = page.lastPage
                    self.seed = page.seed
                    self.canLoadMoreList = page.canLoadMore
                    self.feedErrorMessage = nil
                    let previousID = self.selectedWallpaperID
                    if self.selectedWallpaperID == nil || !page.wallpapers.contains(where: { $0.id == self.selectedWallpaperID }) {
                        self.selectedWallpaperID = page.wallpapers.first?.id
                    }
                    if self.selectedWallpaperID != previousID {
                        self.onSelectionChanged?(self.selectedWallpaper)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                if self.section == searchSection {
                    self.feedErrorMessage = error.localizedDescription
                }
            }
            if self.section == searchSection {
                self.isRefreshingList = false
                self.loadTask = nil
            }
        }
    }

    func loadMoreIfNeeded() {
        guard section != .favorites else { return }
        guard !isRefreshingList, canLoadMoreList else { return }
        let searchSection = section
        let nextPage = currentPage + 1
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            do {
                let page = try await self.performSearch(page: nextPage)
                guard !Task.isCancelled else { return }
                var existing = self.cachedWallpapers[searchSection] ?? []
                let existingIDs = Set(existing.map(\.id))
                let newItems = page.wallpapers.filter { !existingIDs.contains($0.id) }
                existing.append(contentsOf: newItems)
                self.cachedWallpapers[searchSection] = existing
                self.cachedPages[searchSection] = (page.currentPage, page.lastPage, page.seed)
                if self.section == searchSection, self.activeSearchQuery == nil {
                    self.wallpapers = existing
                    self.currentPage = page.currentPage
                    self.lastPage = page.lastPage
                    self.seed = page.seed
                    self.canLoadMoreList = page.canLoadMore
                    self.feedErrorMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                if self.section == searchSection {
                    self.feedErrorMessage = error.localizedDescription
                }
            }
            if self.section == searchSection {
                self.isRefreshingList = false
                self.loadTask = nil
            }
        }
    }

    // MARK: - Search

    func setSearchText(_ text: String) {
        searchText = text
        searchDebounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if activeSearchQuery != nil {
                clearSearch()
            }
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.submitSearch(trimmed)
        }
    }

    func submitSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != activeSearchQuery else { return }
        activeSearchQuery = trimmed
        loadTask?.cancel()
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            let requestQuery = trimmed
            do {
                let page = try await self.performSearch(page: 1, query: requestQuery)
                guard !Task.isCancelled, self.activeSearchQuery == requestQuery else { return }
                self.wallpapers = page.wallpapers
                self.currentPage = page.currentPage
                self.lastPage = page.lastPage
                self.seed = page.seed
                self.canLoadMoreList = page.canLoadMore
                self.feedErrorMessage = nil
                let first = page.wallpapers.first
                self.selectedWallpaperID = first?.id
                self.onSelectionChanged?(first)
            } catch {
                guard !Task.isCancelled, self.activeSearchQuery == requestQuery else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            if self.activeSearchQuery == requestQuery {
                self.isRefreshingList = false
                self.searchTask = nil
            }
        }
    }

    func loadMoreSearchIfNeeded() {
        guard !isRefreshingList, canLoadMoreList, activeSearchQuery != nil else { return }
        let requestQuery = activeSearchQuery
        let nextPage = currentPage + 1
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            do {
                let page = try await self.performSearch(page: nextPage, query: requestQuery)
                guard !Task.isCancelled, self.activeSearchQuery == requestQuery else { return }
                var existingIDs = Set(self.wallpapers.map(\.id))
                let newItems = page.wallpapers.filter { existingIDs.insert($0.id).inserted }
                self.wallpapers.append(contentsOf: newItems)
                self.currentPage = page.currentPage
                self.lastPage = page.lastPage
                self.seed = page.seed
                self.canLoadMoreList = page.canLoadMore
                self.feedErrorMessage = nil
            } catch {
                guard !Task.isCancelled, self.activeSearchQuery == requestQuery else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            if self.activeSearchQuery == requestQuery {
                self.isRefreshingList = false
                self.loadTask = nil
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        loadTask?.cancel()
        loadTask = nil
        activeSearchQuery = nil
        searchText = ""
        canLoadMoreList = false
        isRefreshingList = false
        restoreSectionCache()
    }

    func restoreSectionCache() {
        if section == .favorites {
            refreshFavorites()
            return
        }
        if let cached = cachedWallpapers[section], !cached.isEmpty {
            wallpapers = cached
            (currentPage, lastPage, seed) = cachedPages[section] ?? (1, 1, nil)
            canLoadMoreList = currentPage < lastPage
            feedErrorMessage = nil
            let previousID = selectedWallpaperID
            if selectedWallpaperID == nil || !cached.contains(where: { $0.id == selectedWallpaperID }) {
                selectedWallpaperID = cached.first?.id
            }
            if selectedWallpaperID != previousID {
                onSelectionChanged?(selectedWallpaperID.flatMap { id in cached.first { $0.id == id } })
            }
            if let timestamp = cacheTimestamps[section],
               Date().timeIntervalSince(timestamp) > Self.cacheMaxAge {
                refreshFromNetwork()
            }
        } else {
            wallpapers = []
            selectedWallpaperID = nil
            onSelectionChanged?(nil)
            feedErrorMessage = nil
            canLoadMoreList = false
            refreshFromNetwork()
        }
    }

    // MARK: - Favorites

    private func refreshFavorites() {
        isRefreshingList = true
        feedErrorMessage = nil
        let records = favoritesStore.favorites.filter { $0.sourceID == "wallhaven" }
        let items = WallhavenFavoritesBridge.wallpapers(from: records)
        wallpapers = items
        canLoadMoreList = false
        isRefreshingList = false
        let previousID = selectedWallpaperID
        if selectedWallpaperID == nil || !items.contains(where: { $0.id == selectedWallpaperID }) {
            selectedWallpaperID = items.first?.id
        }
        if selectedWallpaperID != previousID {
            onSelectionChanged?(selectedWallpaperID.flatMap { id in items.first { $0.id == id } })
        }
    }

    /// Call when favorites change externally, to refresh the list if currently viewing favorites.
    func refreshFavoritesIfNeeded() {
        guard section == .favorites else { return }
        refreshFavorites()
    }

    // MARK: - Detail resolution

    var resolvedWallpaper: Wallpaper?
    var isResolvingDetail = false
    private var resolveTask: Task<Void, Never>?

    func resolveDetail(for wallpaper: Wallpaper) {
        if resolvedWallpaper?.id == wallpaper.id { return } // Already resolved.
        if resolveTask != nil {
            resolveTask?.cancel()
            resolveTask = nil
        }
        resolvedWallpaper = wallpaper
        isResolvingDetail = true
        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let full = try await self.apiClient.wallpaper(id: wallpaper.id, apiKey: self.accountStore.apiKey)
                guard !Task.isCancelled else { return }
                self.resolvedWallpaper = full
                // Update the wallpaper in the list with resolved data.
                if let idx = self.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                    self.wallpapers[idx] = full
                }
            } catch {
                // Keep the list-item data; resolvedWallpaper stays as the original.
            }
            guard !Task.isCancelled else { return }
            self.isResolvingDetail = false
        }
    }

    func cancelResolveDetail() {
        resolveTask?.cancel()
        resolveTask = nil
        resolvedWallpaper = nil
        isResolvingDetail = false
    }

    // MARK: - Private

    private func performSearch(page: Int, query: String? = nil) async throws -> WallhavenPage {
        let parameters = WallhavenSearchParameters(
            query: query ?? activeSearchQuery,
            category: category,
            purity: accountStore.purity,
            sorting: sorting,
            order: .desc,
            topRange: .oneMonth,
            resolution: resolution,
            ratio: ratio,
            page: page,
            seed: sorting == .random ? seed : nil,
            collection: nil
        )
        return try await apiClient.search(parameters: parameters, apiKey: accountStore.apiKey)
    }
}
