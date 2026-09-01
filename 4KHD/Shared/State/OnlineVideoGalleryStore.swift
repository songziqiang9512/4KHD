import Foundation
import Observation

@MainActor
@Observable
final class OnlineVideoGalleryStore {
    typealias ListResolver = (URL) async throws -> OnlineVideoListPage
    typealias DetailResolver = (URL) async throws -> OnlineVideoResolvedDetail
    typealias ListURLBuilder = (String, String?) -> URL?
    typealias FilterTitle = (String) -> String
    typealias FavoriteFactory = (OnlineVideoItem) -> FavoriteRecord

    let policySource: OnlineSourcePolicy.Source
    let sourceTitle: String

    private(set) var filter: String
    var searchText = ""
    private(set) var activeSearchQuery: String?
    private(set) var items: [OnlineVideoItem] = []
    private(set) var selectedItemID: OnlineVideoItem.ID?
    private(set) var isRefreshingList = false
    private(set) var listErrorMessage: String?
    private(set) var currentPage = 0
    private(set) var totalPages = 0
    private(set) var nextPageURL: URL?
    private(set) var videoURL: URL?
    private(set) var detailErrorMessage: String?
    private(set) var isResolvingDetail = false

    @ObservationIgnored private let favorites: FavoritesStore
    @ObservationIgnored private let listResolver: ListResolver
    @ObservationIgnored private let detailResolver: DetailResolver
    @ObservationIgnored private let listURL: ListURLBuilder
    @ObservationIgnored private let filterTitle: FilterTitle
    @ObservationIgnored private let makeFavoriteRecord: FavoriteFactory
    @ObservationIgnored private let directoryFilters: Set<String>
    @ObservationIgnored private var directoryTitles: [String: String] = [:]
    @ObservationIgnored private var selectedItemSnapshot: OnlineVideoItem?
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var listRequestToken = UUID()
    @ObservationIgnored private var pendingLoadMore = false
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var detailGeneration = UUID()
    @ObservationIgnored private var listCache: [String: CachedListPage] = [:]

    private struct CachedListPage {
        var items: [OnlineVideoItem]
        var currentPage: Int
        var totalPages: Int
        var nextPageURL: URL?
    }

    init(
        policySource: OnlineSourcePolicy.Source,
        sourceTitle: String,
        defaultFilter: String,
        favorites: FavoritesStore,
        listURL: @escaping ListURLBuilder,
        filterTitle: @escaping FilterTitle,
        listResolver: @escaping ListResolver,
        detailResolver: @escaping DetailResolver,
        makeFavoriteRecord: @escaping FavoriteFactory,
        directoryFilters: Set<String> = []
    ) {
        self.policySource = policySource
        self.sourceTitle = sourceTitle
        filter = defaultFilter
        self.favorites = favorites
        self.listURL = listURL
        self.filterTitle = filterTitle
        self.listResolver = listResolver
        self.detailResolver = detailResolver
        self.makeFavoriteRecord = makeFavoriteRecord
        self.directoryFilters = directoryFilters
    }

    deinit {
        listTask?.cancel()
        detailTask?.cancel()
    }

    var selectedItem: OnlineVideoItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
            ?? selectedItemSnapshot.flatMap { $0.id == selectedItemID ? $0 : nil }
    }

    var canLoadMoreList: Bool {
        nextPageURL != nil
    }

    var hasPlayableVideo: Bool {
        videoURL != nil
    }

    var canStepSelectionBackward: Bool {
        guard let index = selectedIndex else { return false }
        return index > 0
    }

    var canStepSelectionForward: Bool {
        guard let index = selectedIndex else { return false }
        return index + 1 < items.count
    }

    var displayFilterTitle: String {
        directoryTitles[filter] ?? filterTitle(filter)
    }

    var showsDirectoryListing: Bool {
        if !items.isEmpty {
            return items.allSatisfy(\.isDirectoryEntry)
        }
        return directoryFilters.contains(filter)
    }

    var pageStatusText: String {
        let title = displayFilterTitle
        guard totalPages > 0 else { return title }
        return "\(title) · 第 \(max(currentPage, 1))/\(totalPages) 页"
    }

    var favoriteItemIDs: Set<OnlineVideoItem.ID> {
        Set(items.lazy.filter { !$0.isDirectoryEntry && self.favorites.contains(detailURL: $0.detailURL) }.map(\.id))
    }

    func bootstrapIfNeeded() {
        guard items.isEmpty, listTask == nil else { return }
        refreshFromNetwork()
    }

    func setFilter(_ filter: String) {
        guard self.filter != filter || activeSearchQuery != nil else { return }
        self.filter = filter
        searchText = ""
        activeSearchQuery = nil
        if restoreCachedListIfAvailable() {
            if items.allSatisfy(\.isDirectoryEntry) {
                return
            }
        } else {
            resetVisibleList()
        }
        refreshFromNetwork()
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        guard query != activeSearchQuery else { return }
        if applyLocalDirectorySearch(query) {
            return
        }
        activeSearchQuery = query
        if !restoreCachedListIfAvailable() {
            resetVisibleList()
        }
        refreshFromNetwork()
    }

    func clearSearch() {
        guard activeSearchQuery != nil || !searchText.isEmpty else { return }
        searchText = ""
        activeSearchQuery = nil
        if restoreCachedListIfAvailable() {
            if items.allSatisfy(\.isDirectoryEntry) {
                return
            }
        } else {
            resetVisibleList()
        }
        refreshFromNetwork()
    }

    func refreshFromNetwork() {
        guard let url = listURL(filter, activeSearchQuery) else {
            listErrorMessage = "列表地址无效"
            return
        }
        listTask?.cancel()
        listTask = nil
        pendingLoadMore = false
        let token = UUID()
        listRequestToken = token
        listErrorMessage = nil
        isRefreshingList = true
        startListRequest(url: url, replacing: true, token: token)
    }

    func retryLastFailure() {
        if listErrorMessage != nil {
            refreshFromNetwork()
        } else if detailErrorMessage != nil {
            resolveSelectedDetailIfNeeded(force: true)
        }
    }

    func loadMoreListIfNeeded() {
        guard let nextPageURL else { return }
        guard listTask == nil else {
            pendingLoadMore = true
            return
        }
        startListRequest(url: nextPageURL, replacing: false)
    }

    func stepSelection(_ delta: Int) {
        guard delta != 0, let index = selectedIndex else { return }
        let next = index + delta
        guard items.indices.contains(next) else { return }
        select(items[next])
    }

    func select(_ item: OnlineVideoItem, force: Bool = false) {
        guard force || selectedItemID != item.id else { return }
        selectedItemSnapshot = item
        selectedItemID = item.id
        prepareDetail(for: item)
    }

    func resolveSelectedDetailIfNeeded(force: Bool = false) {
        guard let item = selectedItem else { return }
        if !force, videoURL != nil || isResolvingDetail { return }
        detailTask?.cancel()
        detailTask = Task { [weak self] in
            guard let self else { return }
            _ = try? await resolveVideoURL(for: item)
        }
    }

    func resolveVideoURL(for item: OnlineVideoItem) async throws -> URL {
        if item.isDirectoryEntry {
            throw OnlineVideoPlaybackError.notAVideo
        }
        if selectedItemID != item.id {
            select(item)
        }
        let generation = UUID()
        detailGeneration = generation
        isResolvingDetail = true
        detailErrorMessage = nil
        detailTask?.cancel()
        do {
            let detail = try await detailResolver(item.detailURL)
            try Task.checkCancellation()
            guard detailGeneration == generation, selectedItemID == item.id else {
                throw CancellationError()
            }
            videoURL = detail.videoURL
            isResolvingDetail = false
            return detail.videoURL
        } catch {
            if detailGeneration == generation, selectedItemID == item.id {
                videoURL = nil
                if !(error is CancellationError) {
                    detailErrorMessage = error.localizedDescription
                }
                isResolvingDetail = false
            }
            throw error
        }
    }

    func cancelDetailResolution() {
        detailTask?.cancel()
        detailTask = nil
        isResolvingDetail = false
    }

    func isFavorite(_ item: OnlineVideoItem) -> Bool {
        guard !item.isDirectoryEntry else { return false }
        return favorites.contains(detailURL: item.detailURL)
    }

    func toggleFavorite(for item: OnlineVideoItem) async throws {
        guard !item.isDirectoryEntry else { return }
        try await favorites.toggle(makeFavoriteRecord(item))
    }

    private func startListRequest(url: URL, replacing: Bool, token: UUID? = nil) {
        let requestToken = token ?? UUID()
        listRequestToken = requestToken
        isRefreshingList = true
        listErrorMessage = nil
        let cacheKey = currentCacheKey
        listTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await listResolver(url)
                guard !Task.isCancelled,
                      listRequestToken == requestToken,
                      currentCacheKey == cacheKey else { return }
                applyListPage(result, replacing: replacing)
            } catch {
                guard !Task.isCancelled,
                      listRequestToken == requestToken,
                      currentCacheKey == cacheKey else { return }
                listErrorMessage = error.localizedDescription
                finishListRequest(token: requestToken)
            }
        }
    }

    private func applyListPage(_ page: OnlineVideoListPage, replacing: Bool) {
        rememberDirectoryTitles(from: page.items)
        if replacing {
            if items != page.items {
                let previousID = selectedItemID
                items = page.items
                if let previousID, let refreshedSelection = items.first(where: { $0.id == previousID }) {
                    selectedItemSnapshot = refreshedSelection
                    selectedItemID = previousID
                } else {
                    selectedItemSnapshot = items.first
                    selectedItemID = items.first?.id
                    if let selectedItem {
                        prepareDetail(for: selectedItem)
                    } else {
                        clearDetail()
                    }
                }
            }
        } else {
            var existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { existing.insert($0.id).inserted })
            if selectedItem == nil {
                selectedItemSnapshot = items.first
                selectedItemID = items.first?.id
                if let selectedItem { prepareDetail(for: selectedItem) }
            }
        }
        currentPage = page.currentPage
        totalPages = page.totalPages
        nextPageURL = page.nextPageURL
        listCache[currentCacheKey] = CachedListPage(
            items: items,
            currentPage: currentPage,
            totalPages: totalPages,
            nextPageURL: nextPageURL
        )
        finishListRequest(token: listRequestToken)
    }

    @discardableResult
    private func restoreCachedListIfAvailable() -> Bool {
        guard let cached = listCache[currentCacheKey], !cached.items.isEmpty else { return false }
        items = cached.items
        currentPage = cached.currentPage
        totalPages = cached.totalPages
        nextPageURL = cached.nextPageURL
        rememberDirectoryTitles(from: items)
        if let selectedItemID,
           let refreshedSelection = items.first(where: { $0.id == selectedItemID })
        {
            selectedItemSnapshot = refreshedSelection
        } else {
            selectedItemSnapshot = items.first
            selectedItemID = items.first?.id
        }
        if let selectedItem {
            prepareDetail(for: selectedItem)
        } else {
            clearDetail()
        }
        return true
    }

    private func resetVisibleList() {
        items = []
        currentPage = 0
        totalPages = 0
        nextPageURL = nil
        selectedItemID = nil
        selectedItemSnapshot = nil
        listErrorMessage = nil
        clearDetail()
    }

    private func applyLocalDirectorySearch(_ query: String) -> Bool {
        let source = listCache["filter:\(filter)"]?.items
            ?? (items.allSatisfy(\.isDirectoryEntry) ? items : nil)
        guard let source, !source.isEmpty, source.allSatisfy(\.isDirectoryEntry) else { return false }
        activeSearchQuery = query
        items = source.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subtitle.localizedCaseInsensitiveContains(query)
        }
        currentPage = 1
        totalPages = 1
        nextPageURL = nil
        rememberDirectoryTitles(from: source)
        selectedItemSnapshot = items.first
        selectedItemID = items.first?.id
        if let selectedItem {
            prepareDetail(for: selectedItem)
        } else {
            clearDetail()
        }
        return true
    }

    private func rememberDirectoryTitles(from items: [OnlineVideoItem]) {
        for item in items {
            if let filter = item.opensFilter, !item.title.isEmpty {
                directoryTitles[filter] = item.title
            }
            if let authorFilter = item.authorFilter,
               let name = item.authorName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty
            {
                directoryTitles[authorFilter] = name
            }
            for tag in item.tagFilters where !tag.title.isEmpty {
                directoryTitles[tag.filter] = tag.title
            }
        }
    }

    private func finishListRequest(token: UUID) {
        guard listRequestToken == token else { return }
        listTask = nil
        isRefreshingList = false
        if pendingLoadMore {
            pendingLoadMore = false
            loadMoreListIfNeeded()
        }
    }

    private var selectedIndex: Int? {
        guard let selectedItemID else { return nil }
        return items.firstIndex { $0.id == selectedItemID }
    }

    private var currentCacheKey: String {
        if let activeSearchQuery {
            return "search:\(activeSearchQuery)"
        }
        return "filter:\(filter)"
    }

    private func prepareDetail(for item: OnlineVideoItem) {
        detailTask?.cancel()
        detailTask = nil
        detailGeneration = UUID()
        videoURL = nil
        detailErrorMessage = nil
        isResolvingDetail = false
        selectedItemSnapshot = item
    }

    private func clearDetail() {
        detailTask?.cancel()
        detailTask = nil
        detailGeneration = UUID()
        videoURL = nil
        detailErrorMessage = nil
        isResolvingDetail = false
    }
}
