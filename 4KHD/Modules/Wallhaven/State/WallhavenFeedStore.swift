import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WallhavenFeedStore {
    private let logger = Logger(subsystem: "com.songziqiang.4khd", category: "WallhavenFeed")
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
    private var searchLoadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    /// Request token to invalidate stale Task completions.
    private var listRequestToken = UUID()

    private func invalidateListRequests() { listRequestToken = UUID() }
    private func beginListRequest() -> UUID {
        let token = UUID()
        listRequestToken = token
        return token
    }

    /// In-flight markers to prevent duplicate load-more from rapid UI triggers.
    private var inFlightPage: Int?
    private var inFlightSearchPage: Int?
    private var inFlightUploaderPage: Int?

    /// Cached per section preserves items across section switches (currently only .browse).
    private var cachedWallpapers: [WallhavenSection: [Wallpaper]] = [:]
    private var cachedPages: [WallhavenSection: (current: Int, last: Int, seed: String?)] = [:]
    private var cacheTimestamps: [WallhavenSection: Date] = [:]

    private static let cacheMaxAge: TimeInterval = 3600

    private let apiClient: WallhavenAPIClient
    let accountStore: WallhavenAccountStore
    private let preferences: WallhavenContentPreferences
    private let favoritesStore: FavoritesStore

    /// Cache for resolved wallpaper details so favorites/collections don't re-fetch /w/{id} every time.
    private var detailCache: [String: Wallpaper] = [:]

    private static var detailCacheFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let d = dir.appendingPathComponent("4KHD/Wallhaven", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("detail-cache.json")
    }

    var isBrowsingUploader = false
    var uploaderUsername: String?
    private var uploaderPage = 1
    private var uploaderHasMore = true

    /// Saved state for back navigation from uploader view.
    private var savedState: (
        wallpapers: [Wallpaper],
        page: Int,
        lastPage: Int,
        seed: String?,
        canLoadMore: Bool,
        scrollItemID: Wallpaper.ID?,
        searchQuery: String?
    )?

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
        loadDetailCache()
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
        invalidateListRequests()
        clearUploaderBrowsing()
        cancelAllTasks()
        resetInFlightMarkers()
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

    private func cancelAllTasks() {
        loadTask?.cancel(); loadTask = nil
        searchLoadTask?.cancel(); searchLoadTask = nil
        searchTask?.cancel(); searchTask = nil
        searchDebounceTask?.cancel(); searchDebounceTask = nil
    }

    private func resetInFlightMarkers() {
        inFlightPage = nil
        inFlightSearchPage = nil
        inFlightUploaderPage = nil
    }

    // MARK: - Network

    func setSection(_ newSection: WallhavenSection) {
        guard section != newSection else { return }
        invalidateListRequests()
        cancelAllTasks()
        clearUploaderBrowsing()
        resetInFlightMarkers()
        activeSearchQuery = nil
        searchText = ""
        section = newSection
        restoreSectionCache()
    }

    func refreshFromNetwork() {
        // Re-route to current mode so toolbar refresh / footer retry work correctly.
        if isBrowsingUploader, let username = uploaderUsername {
            uploaderPage = 1
            inFlightUploaderPage = 1
            uploaderHasMore = true
            isRefreshingList = true
            feedErrorMessage = nil
            wallpapers = []
            canLoadMoreList = true
            let requestUsername = username
            let requestPurity = accountStore.purity
            let requestApiKey = accountStore.apiKey
            let requestToken = beginListRequest()
            cancelAllTasks()
            loadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let items = try await WallhavenUploaderResolver.resolve(
                        username: requestUsername,
                        page: 1,
                        purity: requestPurity,
                        apiKey: requestApiKey
                    )
                    guard !Task.isCancelled,
                          self.listRequestToken == requestToken,
                          self.isBrowsingUploader,
                          self.uploaderUsername == requestUsername
                    else { return }
                    self.wallpapers = items
                    self.uploaderHasMore = !items.isEmpty
                    self.canLoadMoreList = self.uploaderHasMore
                    self.feedErrorMessage = items.isEmpty ? "未找到 @\(requestUsername) 的作品" : nil
                    self.selectedWallpaperID = items.first?.id
                    self.onSelectionChanged?(items.first)
                } catch {
                    guard !Task.isCancelled,
                          self.listRequestToken == requestToken,
                          self.isBrowsingUploader,
                          self.uploaderUsername == requestUsername
                    else { return }
                    self.feedErrorMessage = error.localizedDescription
                }
                if self.listRequestToken == requestToken {
                    self.isRefreshingList = false
                    self.loadTask = nil
                    self.inFlightUploaderPage = nil
                }
            }
            return
        }
        if section == .favorites {
            refreshFavorites()
            return
        }
        if let query = activeSearchQuery, !query.isEmpty {
            submitSearch(query, force: true)
            return
        }
        isRefreshingList = true
        let requestToken = beginListRequest()
        let (searchParams, searchApiKey) = makeSearchParameters(page: 1)
        inFlightPage = nil
        inFlightSearchPage = nil
        cancelAllTasks()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.feedErrorMessage = nil
            let searchSection = self.section
            do {
                let page = try await self.performSearch(parameters: searchParams, apiKey: searchApiKey)
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.section == searchSection,
                      self.activeSearchQuery == nil
                else { return }
                self.cachedWallpapers[searchSection] = page.wallpapers
                self.cachedPages[searchSection] = (page.currentPage, page.lastPage, page.seed)
                self.cacheTimestamps[searchSection] = Date()
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
            } catch {
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.section == searchSection
                else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            if self.listRequestToken == requestToken {
                self.isRefreshingList = false
                self.loadTask = nil
            }
        }
    }

    func loadMoreIfNeeded() {
        if isBrowsingUploader {
            loadMoreUploaderWorks()
            return
        }
        guard section != .favorites else { return }
        if activeSearchQuery != nil {
            loadMoreSearchIfNeeded()
            return
        }
        guard !isRefreshingList, canLoadMoreList else { return }
        let searchSection = section
        let nextPage = currentPage + 1
        guard inFlightPage != nextPage else { return }
        inFlightPage = nextPage
        isRefreshingList = true
        let requestToken = beginListRequest()
        let (searchParams, searchApiKey) = makeSearchParameters(page: nextPage)
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.feedErrorMessage = nil
            do {
                let page = try await self.performSearch(parameters: searchParams, apiKey: searchApiKey)
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.section == searchSection,
                      self.activeSearchQuery == nil
                else { return }
                var existing = self.cachedWallpapers[searchSection] ?? []
                let existingIDs = Set(existing.map(\.id))
                let newItems = page.wallpapers.filter { !existingIDs.contains($0.id) }
                existing.append(contentsOf: newItems)
                self.cachedWallpapers[searchSection] = existing
                self.cachedPages[searchSection] = (page.currentPage, page.lastPage, page.seed)
                self.wallpapers = existing
                self.currentPage = page.currentPage
                self.lastPage = page.lastPage
                self.seed = page.seed
                self.canLoadMoreList = page.canLoadMore
                self.feedErrorMessage = nil
            } catch {
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.section == searchSection
                else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            if self.listRequestToken == requestToken {
                self.isRefreshingList = false
                self.loadTask = nil
                self.inFlightPage = nil
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

    func submitSearch(_ query: String, force: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard force || trimmed != activeSearchQuery else { return }
        // Exit uploader browsing so load-more goes to search pagination.
        clearUploaderBrowsing()
        activeSearchQuery = trimmed
        isRefreshingList = true
        feedErrorMessage = nil
        cancelAllTasks()
        inFlightSearchPage = nil
        let requestToken = beginListRequest()
        let (searchParams, searchApiKey) = makeSearchParameters(page: 1, query: trimmed)
        let requestQuery = trimmed
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.performSearch(parameters: searchParams, apiKey: searchApiKey)
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.activeSearchQuery == requestQuery
                else { return }
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
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.activeSearchQuery == requestQuery
                else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            if self.listRequestToken == requestToken {
                self.isRefreshingList = false
                self.searchTask = nil
            }
        }
    }

    func loadMoreSearchIfNeeded() {
        guard !isRefreshingList, canLoadMoreList, activeSearchQuery != nil else { return }
        let requestQuery = activeSearchQuery
        let nextPage = currentPage + 1
        guard inFlightSearchPage != nextPage else { return }
        inFlightSearchPage = nextPage
        isRefreshingList = true
        let requestToken = beginListRequest()
        let (searchParams, searchApiKey) = makeSearchParameters(page: nextPage, query: requestQuery)
        searchLoadTask?.cancel()
        searchLoadTask = Task { [weak self] in
            guard let self else { return }
            self.feedErrorMessage = nil
            do {
                let page = try await self.performSearch(parameters: searchParams, apiKey: searchApiKey)
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.activeSearchQuery == requestQuery
                else { return }
                var existingIDs = Set(self.wallpapers.map(\.id))
                let newItems = page.wallpapers.filter { existingIDs.insert($0.id).inserted }
                self.wallpapers.append(contentsOf: newItems)
                self.currentPage = page.currentPage
                self.lastPage = page.lastPage
                self.seed = page.seed
                self.canLoadMoreList = page.canLoadMore
                self.feedErrorMessage = nil
            } catch {
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.activeSearchQuery == requestQuery
                else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            if self.listRequestToken == requestToken {
                self.isRefreshingList = false
                self.searchLoadTask = nil
                self.inFlightSearchPage = nil
            }
        }
    }

    func clearSearch() {
        invalidateListRequests()
        cancelAllTasks()
        resetInFlightMarkers()
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
        currentPage = 1
        lastPage = 1
        seed = nil
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
        guard section == .favorites, !isBrowsingUploader else { return }
        refreshFavorites()
    }

    // MARK: - Uploader browsing

    func showUploaderWorks(username: String) {
        guard !isBrowsingUploader || uploaderUsername != username else { return }
        // Save current state for back navigation. When switching between uploaders,
        // keep the original state so Back returns to where uploader browsing began.
        if !isBrowsingUploader {
            savedState = (
                wallpapers: wallpapers,
                page: currentPage,
                lastPage: lastPage,
                seed: seed,
                canLoadMore: canLoadMoreList,
                scrollItemID: selectedWallpaperID,
                searchQuery: activeSearchQuery
            )
        }
        cancelAllTasks()
        isBrowsingUploader = true
        uploaderUsername = username
        uploaderPage = 1
        uploaderHasMore = true
        inFlightUploaderPage = 1
        isRefreshingList = true
        feedErrorMessage = nil
        wallpapers = []
        canLoadMoreList = true
        let requestToken = beginListRequest()
        let requestUsername = username
        let requestPurity = accountStore.purity
        let requestApiKey = accountStore.apiKey
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await WallhavenUploaderResolver.resolve(
                    username: requestUsername,
                    page: 1,
                    purity: requestPurity,
                    apiKey: requestApiKey
                )
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.isBrowsingUploader,
                      self.uploaderUsername == requestUsername
                else { return }
                self.wallpapers = items
                self.uploaderHasMore = !items.isEmpty
                self.canLoadMoreList = self.uploaderHasMore
                self.feedErrorMessage = items.isEmpty ? "未找到 @\(requestUsername) 的作品" : nil
                self.selectedWallpaperID = items.first?.id
                self.onSelectionChanged?(items.first)
            } catch {
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.isBrowsingUploader,
                      self.uploaderUsername == requestUsername
                else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            guard self.isBrowsingUploader, self.listRequestToken == requestToken else { return }
            self.isRefreshingList = false
            self.loadTask = nil
            self.inFlightUploaderPage = nil
        }
    }

    private func loadMoreUploaderWorks() {
        guard isBrowsingUploader, uploaderHasMore, !isRefreshingList,
              let username = uploaderUsername else { return }
        let nextPage = uploaderPage + 1
        guard inFlightUploaderPage != nextPage else { return }
        inFlightUploaderPage = nextPage
        let requestToken = beginListRequest()
        let requestUsername = username
        let requestPurity = accountStore.purity
        let requestApiKey = accountStore.apiKey
        let requestPage = nextPage
        loadTask?.cancel()
        isRefreshingList = true
        feedErrorMessage = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await WallhavenUploaderResolver.resolve(
                    username: requestUsername,
                    page: requestPage,
                    purity: requestPurity,
                    apiKey: requestApiKey
                )
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.isBrowsingUploader,
                      self.uploaderUsername == requestUsername
                else { return }
                if !items.isEmpty {
                    let existingIDs = Set(self.wallpapers.map(\.id))
                    let newItems = items.filter { !existingIDs.contains($0.id) }
                    self.wallpapers.append(contentsOf: newItems)
                    self.uploaderPage = requestPage
                }
                self.uploaderHasMore = !items.isEmpty
                self.canLoadMoreList = self.uploaderHasMore
                self.feedErrorMessage = nil
            } catch {
                guard !Task.isCancelled,
                      self.listRequestToken == requestToken,
                      self.isBrowsingUploader,
                      self.uploaderUsername == requestUsername
                else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            guard self.isBrowsingUploader, self.listRequestToken == requestToken else { return }
            self.isRefreshingList = false
            self.loadTask = nil
            self.inFlightUploaderPage = nil
        }
    }

    func restorePreviousBrowseState() {
        guard isBrowsingUploader else { return }
        invalidateListRequests()
        cancelAllTasks()
        guard let saved = savedState else {
            clearUploaderBrowsing()
            restoreSectionCache()
            return
        }
        wallpapers = saved.wallpapers
        currentPage = saved.page
        lastPage = saved.lastPage
        seed = saved.seed
        activeSearchQuery = saved.searchQuery
        if saved.searchQuery != nil {
            searchText = saved.searchQuery ?? ""
        }
        canLoadMoreList = saved.canLoadMore
        isRefreshingList = false
        feedErrorMessage = nil
        selectedWallpaperID = saved.scrollItemID
        onSelectionChanged?(saved.scrollItemID.flatMap { id in saved.wallpapers.first { $0.id == id } })
        clearUploaderBrowsing()
    }

    private func clearUploaderBrowsing() {
        isBrowsingUploader = false
        uploaderUsername = nil
        uploaderPage = 1
        uploaderHasMore = false
        savedState = nil
        inFlightUploaderPage = nil
    }

    // MARK: - Detail resolution

    var resolvedWallpaper: Wallpaper?
    var isResolvingDetail = false
    private var resolveTask: Task<Void, Never>?

    func resolveDetail(for wallpaper: Wallpaper) {
        // If already resolving this wallpaper, skip duplicate.
        if resolvedWallpaper?.id == wallpaper.id, isResolvingDetail { return }

        // Cancel any in-flight resolve before cache check, so a stale task
        // from a previous wallpaper cannot overwrite the new selection.
        resolveTask?.cancel()
        resolveTask = nil
        isResolvingDetail = false

        // Check cache first.
        if let cached = detailCache[wallpaper.id] {
            resolvedWallpaper = cached
            if let idx = wallpapers.firstIndex(where: { $0.id == wallpaper.id }) {
                wallpapers[idx] = cached
            }
            return
        }

        resolvedWallpaper = wallpaper
        isResolvingDetail = true
        let requestID = wallpaper.id
        let requestApiKey = accountStore.apiKey
        resolveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let full = try await self.apiClient.wallpaper(id: requestID, apiKey: requestApiKey)
                guard !Task.isCancelled,
                      self.resolvedWallpaper?.id == requestID
                else { return }
                self.resolvedWallpaper = full
                if let idx = self.wallpapers.firstIndex(where: { $0.id == requestID }) {
                    self.wallpapers[idx] = full
                }
                self.detailCache[full.id] = full
                self.saveDetailCache()
            } catch {
                logger.error("Failed to resolve wallpaper detail: \(error.localizedDescription)")
                // Keep the list-item data; resolvedWallpaper stays as the original.
            }
            guard !Task.isCancelled,
                  self.resolvedWallpaper?.id == requestID
            else { return }
            self.isResolvingDetail = false
            self.resolveTask = nil
        }
    }

    func cancelResolveDetail() {
        resolveTask?.cancel()
        resolveTask = nil
        resolvedWallpaper = nil
        isResolvingDetail = false
    }

    // MARK: - Detail cache

    private func loadDetailCache() {
        guard let url = Self.detailCacheFileURL,
              let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode([String: Wallpaper].self, from: data) else { return }
        detailCache = cached
    }

    private static let maxDetailCacheEntries = 500

    private func saveDetailCache() {
        // Prune oldest entries if over the limit before saving.
        if detailCache.count > Self.maxDetailCacheEntries {
            let sorted = detailCache.sorted { lhs, rhs in
                let lhsHasDate = lhs.value.createdAt != nil
                let rhsHasDate = rhs.value.createdAt != nil
                if lhsHasDate != rhsHasDate { return lhsHasDate }
                return (lhs.value.createdAt ?? Date.distantPast) > (rhs.value.createdAt ?? Date.distantPast)
            }
            let kept = sorted.prefix(Self.maxDetailCacheEntries).map { ($0.key, $0.value) }
            detailCache = Dictionary(uniqueKeysWithValues: kept)
        }
        guard let url = Self.detailCacheFileURL,
              let data = try? JSONEncoder().encode(detailCache) else { return }
        try? data.write(to: url, options: .atomicWrite)
    }

    // MARK: - Private

    private func makeSearchParameters(page: Int, query: String? = nil) -> (WallhavenSearchParameters, String?) {
        let p = WallhavenSearchParameters(
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
        return (p, accountStore.apiKey)
    }

    private func performSearch(parameters: WallhavenSearchParameters, apiKey: String?) async throws -> WallhavenPage {
        try await apiClient.search(parameters: parameters, apiKey: apiKey)
    }
}
