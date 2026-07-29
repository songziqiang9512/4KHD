import Foundation

/// 线上 / 收藏列表 + 搜索 + 分页刷新。
/// 不管图集内部的 slot / page resolution（那是 `GalleryDetailStore` 的事）。
/// 选中变化时调用注入的 `onSelectionChanged` 通知协调者（`FourKHDGalleryStore`），让 detail
/// 自行 prepare。
@MainActor
@Observable
final class GalleryFeedStore {
    var section: GallerySection = .latest {
        didSet {
            guard section != oldValue else { return }
            clearSearchState()
            selectFirstItemIfNeeded(force: true)
            refreshSectionIfNeeded()
            if section == .favorites {
                Task { [weak self] in
                    guard let self else { return }
                    await favoritesStore.reloadFromDisk()
                    guard self.section == .favorites else { return }
                    self.selectFirstItemIfNeeded(force: true)
                }
            }
        }
    }
    var selectedItemID: GalleryItem.ID?
    var searchText = ""
    private(set) var activeSearchQuery: String?
    private(set) var visibleCount = 18
    private(set) var isRefreshingList = false
    var errorMessage: String?

    @ObservationIgnored private var library = ApifyLibrary()
    @ObservationIgnored private var searchItems: [GalleryItem] = []
    @ObservationIgnored private var searchNextPageURL: URL?
    @ObservationIgnored private var searchRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSearchLoadMore = false
    @ObservationIgnored private var listRefreshTasks: [GallerySection: Task<Void, Never>] = [:]
    @ObservationIgnored private var listNextPageURLs: [GallerySection: URL] = [:]
    @ObservationIgnored private var pendingListLoadMoreSections: Set<GallerySection> = []
    @ObservationIgnored private var autoRefreshAttemptedSections: Set<GallerySection> = []

    /// 由 `FourKHDGalleryStore` 注入；feed 负责把当前选中 item 快照传出去，避免协调者再回读派生状态。
    @ObservationIgnored var onSelectionChanged: ((GalleryItem?) -> Void)?

    private let favoritesStore: FavoritesStore

    init(favoritesStore: FavoritesStore) {
        self.favoritesStore = favoritesStore
    }

    // MARK: - 派生

    var allItems: [GalleryItem] {
        if activeSearchQuery != nil { return searchItems }
        if section == .favorites { return GalleryFavoritesBridge.galleryItems(from: favoritesStore.favorites) }
        return library.items(in: section)
    }

    var visibleItems: [GalleryItem] {
        Array(allItems.prefix(visibleCount))
    }

    var canLoadMoreList: Bool {
        if visibleCount < allItems.count { return true }
        if activeSearchQuery != nil { return searchNextPageURL != nil }
        if section == .favorites { return false }
        return listNextPageURLs[section] != nil
    }

    var selectedItem: GalleryItem? {
        guard let selectedItemID else { return nil }
        return allItems.first { $0.id == selectedItemID }
    }

    // MARK: - 选择

    func select(_ item: GalleryItem, force: Bool = false) {
        if !force, selectedItemID == item.id { return }
        selectedItemID = item.id
        notifySelectionChanged()
    }

    func selectFirstItemIfNeeded(force: Bool) {
        visibleCount = 18
        guard let first = allItems.first else {
            selectedItemID = nil
            notifySelectionChanged()
            return
        }
        if force || selectedItem == nil {
            selectedItemID = first.id
            notifySelectionChanged()
        }
    }

    // MARK: - 加载更多 / 刷新

    func loadMoreListIfNeeded() {
        if activeSearchQuery != nil {
            loadMoreSearchIfNeeded()
            return
        }
        guard section.isNetworkBacked else {
            visibleCount = min(visibleCount + 18, allItems.count)
            return
        }
        if visibleCount < allItems.count {
            visibleCount = min(visibleCount + 18, allItems.count)
            return
        }
        loadNextListPageIfNeeded()
    }

    func refreshFromNetwork() {
        if activeSearchQuery != nil {
            submitSearch(force: true)
            return
        }
        guard section.isNetworkBacked else { return }
        autoRefreshAttemptedSections.insert(section)
        let currentSection = section
        listRefreshTasks[currentSection]?.cancel()
        errorMessage = nil
        isRefreshingList = true
        listRefreshTasks[currentSection] = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolve(section: currentSection)
                guard !Task.isCancelled else { return }
                self?.applyNetworkPage(page, section: currentSection)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishListRefresh(section: currentSection, errorMessage: "网络请求失败")
            }
        }
    }

    func bootstrapIfNeeded() {
        refreshSectionIfNeeded()
    }

    // MARK: - 搜索

    func submitSearch(force: Bool = false) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        guard force || query != activeSearchQuery else { return }
        activeSearchQuery = query
        visibleCount = 18
        selectedItemID = nil
        searchItems = []
        searchNextPageURL = nil
        pendingSearchLoadMore = false
        searchRefreshTask?.cancel()
        listRefreshTasks.values.forEach { $0.cancel() }
        listRefreshTasks.removeAll()
        errorMessage = nil
        isRefreshingList = true
        let requestQuery = query
        searchRefreshTask = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolveSearch(query: requestQuery)
                guard !Task.isCancelled,
                      self?.activeSearchQuery == requestQuery
                else { return }
                self?.applySearchPage(page, replacing: true)
            } catch {
                guard !Task.isCancelled,
                      self?.activeSearchQuery == requestQuery
                else { return }
                self?.errorMessage = "搜索失败"
                self?.finishSearchRefresh()
            }
        }
    }

    func clearSearch() {
        searchRefreshTask?.cancel()
        searchRefreshTask = nil
        clearSearchState()
        errorMessage = nil
        isRefreshingList = false
        selectFirstItemIfNeeded(force: true)
    }

    // MARK: - 内部

    private func loadNextListPageIfNeeded() {
        let currentSection = section
        guard listRefreshTasks[currentSection] == nil else {
            pendingListLoadMoreSections.insert(currentSection)
            return
        }
        guard let nextPageURL = listNextPageURLs[currentSection] else { return }
        errorMessage = nil
        isRefreshingList = true
        listRefreshTasks[currentSection] = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolve(pageURL: nextPageURL, section: currentSection)
                guard !Task.isCancelled else { return }
                self?.appendNetworkPage(page, section: currentSection)
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishListRefresh(section: currentSection, errorMessage: "网络请求失败")
            }
        }
    }

    private func applyNetworkPage(_ page: SiteListPage, section: GallerySection) {
        let items = page.items
        guard !items.isEmpty else {
            finishListRefresh(section: section)
            return
        }

        library = library.replacing(section: section, with: items)
        listNextPageURLs[section] = page.nextPageURL
        guard section == self.section, activeSearchQuery == nil else {
            finishListRefresh(section: section)
            return
        }

        let oldSelectedID = selectedItemID
        visibleCount = min(visibleCount, allItems.count)

        let stillHasSelection = oldSelectedID.flatMap { id in
            allItems.first { $0.id == id }
        } != nil

        if !stillHasSelection {
            selectedItemID = allItems.first?.id
        }
        // 即便选中 ID 没变，item 对象可能被替换（新的 pageURLs 等），让 detail 重建。
        notifySelectionChanged()

        finishListRefresh(section: section)
    }

    private func appendNetworkPage(_ page: SiteListPage, section: GallerySection) {
        guard !page.items.isEmpty else {
            listNextPageURLs[section] = page.nextPageURL
            finishListRefresh(section: section)
            return
        }
        let oldCount = section == self.section ? allItems.count : 0
        library = library.appending(section: section, items: page.items)
        listNextPageURLs[section] = page.nextPageURL
        if section == self.section, activeSearchQuery == nil {
            visibleCount = min(max(visibleCount + 18, oldCount + 1), allItems.count)
        }
        finishListRefresh(section: section)
    }

    private func finishListRefresh(section: GallerySection, errorMessage: String? = nil) {
        listRefreshTasks[section] = nil
        guard section == self.section else { return }
        // Do not clear search loading/error state from a stale list task.
        if activeSearchQuery != nil { return }
        if let errorMessage {
            self.errorMessage = errorMessage
        }
        isRefreshingList = false
        if pendingListLoadMoreSections.remove(section) != nil {
            loadMoreListIfNeeded()
        }
    }

    private func loadMoreSearchIfNeeded() {
        if visibleCount < allItems.count {
            visibleCount = min(visibleCount + 18, allItems.count)
            return
        }
        guard searchRefreshTask == nil else {
            pendingSearchLoadMore = true
            return
        }
        guard let nextPageURL = searchNextPageURL else { return }
        let requestQuery = activeSearchQuery
        errorMessage = nil
        isRefreshingList = true
        searchRefreshTask = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolveSearch(pageURL: nextPageURL)
                guard !Task.isCancelled,
                      self?.activeSearchQuery == requestQuery
                else { return }
                self?.applySearchPage(page, replacing: false)
            } catch {
                guard !Task.isCancelled,
                      self?.activeSearchQuery == requestQuery
                else { return }
                self?.errorMessage = "搜索失败"
                self?.finishSearchRefresh()
            }
        }
    }

    private func applySearchPage(_ page: SiteListPage, replacing: Bool) {
        if replacing {
            searchItems = page.items
        } else {
            let oldCount = searchItems.count
            var existingIDs = Set(searchItems.map(\.id))
            searchItems.append(contentsOf: page.items.filter { existingIDs.insert($0.id).inserted })
            visibleCount = min(max(visibleCount + 18, oldCount + 1), allItems.count)
        }
        searchNextPageURL = page.nextPageURL

        if replacing {
            selectedItemID = searchItems.first?.id
            notifySelectionChanged()
        }
        finishSearchRefresh()
    }

    private func notifySelectionChanged() {
        onSelectionChanged?(selectedItem)
    }

    private func finishSearchRefresh() {
        searchRefreshTask = nil
        isRefreshingList = false
        if pendingSearchLoadMore {
            pendingSearchLoadMore = false
            loadMoreSearchIfNeeded()
        }
    }

    private func refreshSectionIfNeeded() {
        guard section.isNetworkBacked else { return }
        guard autoRefreshAttemptedSections.insert(section).inserted else { return }
        refreshFromNetwork()
    }

    private func clearSearchState() {
        activeSearchQuery = nil
        searchText = ""
        searchItems = []
        searchNextPageURL = nil
        pendingSearchLoadMore = false
    }
}
