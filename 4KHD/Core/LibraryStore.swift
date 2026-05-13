import Foundation

@MainActor
@Observable
final class LibraryStore {
    var section: GallerySection = .latest {
        didSet {
            clearSearchState()
            selectFirstItemIfNeeded(force: true)
            refreshFromNetwork()
        }
    }
    var selectedItemID: GalleryItem.ID?
    var selectedImageIndex = 0
    private(set) var visibleCount = 18
    private(set) var loadedImageSlots: [ImageSlot] = []
    private(set) var prefetchPageURL: URL?
    private(set) var isRefreshingList = false
    var isFullscreenViewerPresented = false
    var searchText = ""
    private(set) var activeSearchQuery: String?

    // 收藏要被 isFavorite(_:) 间接读到，所以让 @Observable 跟踪它。
    private var favorites: [FavoriteGalleryItem] = []

    // 以下都是纯内部状态，view 永远不会读 —— 用 @ObservationIgnored 关掉自动跟踪，
    // 减少不必要的 invalidate。
    @ObservationIgnored private var library = ApifyLibrary()
    @ObservationIgnored private var searchItems: [GalleryItem] = []
    @ObservationIgnored private var searchNextPageURL: URL?
    @ObservationIgnored private var searchRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSearchLoadMore = false
    @ObservationIgnored private var listRefreshTasks: [GallerySection: Task<Void, Never>] = [:]
    @ObservationIgnored private var listNextPageURLs: [GallerySection: URL] = [:]
    @ObservationIgnored private var pendingListLoadMoreSections: Set<GallerySection> = []
    @ObservationIgnored private var itemPageCursors: [GalleryItem.ID: Int] = [:]
    @ObservationIgnored private var resolvedPageURLs: [GalleryItem.ID: [URL]] = [:]
    @ObservationIgnored private var requestedDetailPageURLs: [GalleryItem.ID: Set<URL>] = [:]
    @ObservationIgnored private var detailPageTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingSelectionIndex: Int?
    @ObservationIgnored private static let favoritesDefaultsKey = "com.songziqiang.4khd.favoriteItems.v1"

    init() {
        loadFavorites()
        selectFirstItemIfNeeded(force: true)
    }

    var allItems: [GalleryItem] {
        if activeSearchQuery != nil {
            return searchItems
        }
        if section == .favorites {
            return favorites.compactMap(Self.favoriteToGalleryItem)
        }
        return library.items(in: section)
    }

    var visibleItems: [GalleryItem] {
        Array(allItems.prefix(visibleCount))
    }

    var canLoadMoreList: Bool {
        if visibleCount < allItems.count {
            return true
        }
        if activeSearchQuery != nil {
            return searchNextPageURL != nil
        }
        if section == .favorites {
            return false
        }
        return listNextPageURLs[section] != nil
    }

    var selectedItem: GalleryItem? {
        allItems.first { $0.id == selectedItemID } ?? allItems.first
    }

    var selectedSlot: ImageSlot? {
        guard loadedImageSlots.indices.contains(selectedImageIndex) else { return loadedImageSlots.first }
        return loadedImageSlots[selectedImageIndex]
    }

    var upcomingKnownImageURLs: [URL] {
        let startIndex = max(selectedImageIndex + 1, 0)
        guard startIndex < loadedImageSlots.count else { return [] }
        return loadedImageSlots[startIndex...]
            .prefix(8)
            .compactMap(\.knownURL)
    }

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

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        guard query != activeSearchQuery else { return }
        activeSearchQuery = query
        visibleCount = 18
        selectedItemID = nil
        loadedImageSlots = []
        selectedImageIndex = 0
        prefetchPageURL = nil
        searchItems = []
        searchNextPageURL = nil
        searchRefreshTask?.cancel()
        listRefreshTasks.values.forEach { $0.cancel() }
        listRefreshTasks.removeAll()
        isRefreshingList = true
        searchRefreshTask = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolveSearch(query: query)
                self?.applySearchPage(page, replacing: true)
            } catch {
                self?.finishSearchRefresh()
            }
        }
    }

    func clearSearch() {
        searchRefreshTask?.cancel()
        searchRefreshTask = nil
        clearSearchState()
        isRefreshingList = false
        selectFirstItemIfNeeded(force: true)
    }

    func refreshFromNetwork() {
        if activeSearchQuery != nil {
            submitSearch()
            return
        }
        guard section.isNetworkBacked else { return }
        let currentSection = section
        listRefreshTasks[currentSection]?.cancel()
        isRefreshingList = true
        listRefreshTasks[currentSection] = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolve(section: currentSection)
                self?.applyNetworkPage(page, section: currentSection)
            } catch {
                self?.finishListRefresh(section: currentSection)
            }
        }
    }

    private func loadNextListPageIfNeeded() {
        let currentSection = section
        guard listRefreshTasks[currentSection] == nil else {
            pendingListLoadMoreSections.insert(currentSection)
            return
        }
        guard let nextPageURL = listNextPageURLs[currentSection] else { return }

        isRefreshingList = true
        listRefreshTasks[currentSection] = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolve(pageURL: nextPageURL, section: currentSection)
                self?.appendNetworkPage(page, section: currentSection)
            } catch {
                self?.finishListRefresh(section: currentSection)
            }
        }
    }

    private func applyNetworkPage(_ page: SiteListPage, section: GallerySection) {
        guard activeSearchQuery == nil else {
            finishListRefresh(section: section)
            return
        }
        let items = page.items
        guard !items.isEmpty else {
            finishListRefresh(section: section)
            return
        }
        let selectedID = selectedItemID
        let selectedURL = selectedSlot?.pageURL
        let selectedIndex = selectedImageIndex

        library = library.replacing(section: section, with: items)
        listNextPageURLs[section] = page.nextPageURL
        visibleCount = min(visibleCount, allItems.count)

        if let selectedID, allItems.contains(where: { $0.id == selectedID }) {
            selectedItemID = selectedID
        } else {
            selectedItemID = allItems.first?.id
        }

        if let selectedID,
           let item = allItems.first(where: { $0.id == selectedID }) {
            rebuildInitialSlots(for: item)
            if let selectedURL,
               let index = loadedImageSlots.firstIndex(where: { $0.pageURL == selectedURL }) {
                selectedImageIndex = min(selectedIndex, index)
            }
        } else if let first = allItems.first {
            rebuildInitialSlots(for: first)
        }
        finishListRefresh(section: section)
    }

    private func appendNetworkPage(_ page: SiteListPage, section: GallerySection) {
        guard !page.items.isEmpty else {
            listNextPageURLs[section] = page.nextPageURL
            finishListRefresh(section: section)
            return
        }

        let oldCount = allItems.count
        library = library.appending(section: section, items: page.items)
        listNextPageURLs[section] = page.nextPageURL
        if section == self.section {
            visibleCount = min(max(visibleCount + 18, oldCount + 1), allItems.count)
        }
        finishListRefresh(section: section)
    }

    private func finishListRefresh(section: GallerySection) {
        listRefreshTasks[section] = nil
        if section == self.section {
            isRefreshingList = false
            if pendingListLoadMoreSections.remove(section) != nil {
                loadMoreListIfNeeded()
            }
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

        isRefreshingList = true
        searchRefreshTask = Task { [weak self] in
            do {
                let page = try await SiteListResolver.resolveSearch(pageURL: nextPageURL)
                self?.applySearchPage(page, replacing: false)
            } catch {
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
            if let first = searchItems.first {
                rebuildInitialSlots(for: first)
            }
        }
        finishSearchRefresh()
    }

    private func finishSearchRefresh() {
        searchRefreshTask = nil
        isRefreshingList = false
        if pendingSearchLoadMore {
            pendingSearchLoadMore = false
            loadMoreSearchIfNeeded()
        }
    }

    private func clearSearchState() {
        activeSearchQuery = nil
        searchText = ""
        searchItems = []
        searchNextPageURL = nil
        pendingSearchLoadMore = false
    }

    func select(_ item: GalleryItem, force: Bool = false) {
        guard force || selectedItem?.detailURL != item.detailURL else { return }
        selectedItemID = item.id
        selectedImageIndex = 0
        rebuildInitialSlots(for: item)
    }

    func toggleFavorite(for item: GalleryItem) {
        if favorites.contains(where: { $0.detailURL == item.detailURL.absoluteString }) {
            favorites.removeAll { $0.detailURL == item.detailURL.absoluteString }
            DetailPageImageCache.shared.setPersistent(false, forDetailURL: item.detailURL)
        } else {
            favorites.append(Self.galleryToFavorite(item))
            DetailPageImageCache.shared.setPersistent(true, forDetailURL: item.detailURL)
        }
        saveFavorites()
        if section == .favorites {
            selectFirstItemIfNeeded(force: true)
        }
    }

    func isFavorite(_ item: GalleryItem) -> Bool {
        return favorites.contains(where: { $0.detailURL == item.detailURL.absoluteString })
    }

    func isCached(_ item: GalleryItem) -> Bool {
        return DetailPageImageCache.shared.containsCachedPage(forDetailURL: item.detailURL)
    }

    func selectImage(at index: Int) {
        guard index >= 0 else { return }
        if index >= loadedImageSlots.count {
            // 还没加载到这张：尝试拉下一页，并挂上 pendingSelectionIndex，等 slot 到位后跳过去。
            ensureNextDetailPageLoaded(reason: .selectedBeyondLoadedRange)
            pendingSelectionIndex = loadedImageSlots.count
            return
        }
        selectedImageIndex = index
        ensureNextDetailPageLoadedIfApproachingEnd(from: index)
    }

    func stepImage(_ delta: Int) {
        let nextIndex = selectedImageIndex + delta
        if delta > 0, nextIndex >= loadedImageSlots.count {
            // 一律尝试一次"加载下一页"。如果 cursor 还有空间，会真的请求；如果已经满了，
            // 也无所谓——之前请求的还在路上，会在 chainLoadIfNeeded 里链式接力。
            // 关键：pendingSelectionIndex 一定设上，新 slot 一到就跳过去。
            // ⚠️ 不要在这里 force-restart 当前页，否则会把已在解析的页 task 反复打断。
            ensureNextDetailPageLoaded(reason: .steppedPastLoadedRange)
            pendingSelectionIndex = loadedImageSlots.count
            return
        }
        selectImage(at: nextIndex)
    }

    @discardableResult
    func ensureNextDetailPageLoaded(reason: DetailPageLoadReason) -> Bool {
        guard let item = selectedItem else { return false }
        let cursor = itemPageCursors[item.id, default: 1]
        let pageURLs = pageURLs(for: item)
        guard cursor < pageURLs.count else { return false }
        let pageURL = pageURLs[cursor]
        guard requestedDetailPageURLs[item.id, default: []].insert(pageURL).inserted else {
            // 已发过请求但还没回，视为"在路上"。返回 true 让上层照常挂 pendingSelectionIndex。
            return true
        }
        itemPageCursors[item.id] = cursor + 1
        prefetchPageURL = pageURL
        resolveDetailPage(pageURL)
        return true
    }

    private func ensureNextDetailPageLoadedIfApproachingEnd(from index: Int) {
        guard loadedImageSlots.count - index <= 6 else { return }
        ensureNextDetailPageLoaded(reason: .approachingLoadedEnd)
    }

    func registerResolvedPage(_ page: ResolvedImagePage) {
        guard let item = selectedItem else { return }
        if isFavorite(item) {
            DetailPageImageCache.shared.setPersistent(true, forDetailURL: item.detailURL)
        }
        // @Observable 不再有 objectWillChange.send()；
        // 后续对 loadedImageSlots / selectedImageIndex 的写入会自动 invalidate 订阅。
        let isExpectedPage = pageURLs(for: item).contains(page.pageURL)
            || loadedImageSlots.contains(where: { $0.pageURL == page.pageURL })
            || requestedDetailPageURLs[item.id, default: []].contains(page.pageURL)
        guard isExpectedPage else { return }
        mergeResolvedPageURLs(page.pageURLs, for: item)
        if prefetchPageURL == page.pageURL {
            prefetchPageURL = nil
        }
        detailPageTasks[page.pageURL.absoluteString] = nil

        if let firstIndex = loadedImageSlots.firstIndex(where: { $0.pageURL == page.pageURL }),
           let lastIndex = loadedImageSlots.lastIndex(where: { $0.pageURL == page.pageURL }) {
            let startDisplayIndex = loadedImageSlots[firstIndex].displayIndex
            let resolvedSlots = page.imageURLs.enumerated().map { offset, imageURL in
                ImageSlot(
                    id: "\(item.id)-\(startDisplayIndex + offset)",
                    displayIndex: startDisplayIndex + offset,
                    pageURL: page.pageURL,
                    pageImageIndex: offset,
                    knownURL: imageURL
                )
            }
            loadedImageSlots.replaceSubrange(firstIndex...lastIndex, with: resolvedSlots)
            selectedImageIndex = min(selectedImageIndex, max(loadedImageSlots.count - 1, 0))
            applyPendingSelectionIfPossible()
            chainLoadIfNeeded()
            return
        }
        appendResolvedSlots(for: item, page: page)
        applyPendingSelectionIfPossible()
        chainLoadIfNeeded()
    }

    /// 一页解析回来之后，无脑尝试拉下一页。
    /// - `ensureNextDetailPageLoaded` 内部会自己判断 cursor 是否还有空间，没有就直接 no-op；
    /// - 这条让 pageURLs 在某一页的 HTML 里继续长出来（比如 page3 的页脚揭示了 page6..page10）时，
    ///   链路自动跟进，不需要用户再戳按钮；
    /// - 用户已经挂着 `pendingSelectionIndex`（连点过下一张）时，也确保接力。
    private func chainLoadIfNeeded() {
        ensureNextDetailPageLoaded(reason: .approachingLoadedEnd)
    }

    private func selectFirstItemIfNeeded(force: Bool) {
        visibleCount = 18
        guard let first = allItems.first else {
            selectedItemID = nil
            loadedImageSlots = []
            selectedImageIndex = 0
            prefetchPageURL = nil
            return
        }
        if force || selectedItemID == nil {
            select(first, force: force)
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: Self.favoritesDefaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteGalleryItem].self, from: data) else {
            favorites = []
            return
        }
        favorites = decoded
        for favorite in favorites {
            guard let detailURL = URL(string: favorite.detailURL) else { continue }
            DetailPageImageCache.shared.setPersistent(true, forDetailURL: detailURL)
        }
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: Self.favoritesDefaultsKey)
    }

    private static func galleryToFavorite(_ item: GalleryItem) -> FavoriteGalleryItem {
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

    private static func favoriteToGalleryItem(_ favorite: FavoriteGalleryItem) -> GalleryItem? {
        guard let section = GallerySection(rawValue: favorite.sectionRawValue),
              section != .favorites,
              let detailURL = URL(string: favorite.detailURL) else {
            return nil
        }
        let coverURL = favorite.coverURL.flatMap(URL.init(string:))
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
            pageURLs: [detailURL],
            sampleImageURLs: coverURL.map { [$0] } ?? []
        )
    }

    private func rebuildInitialSlots(for item: GalleryItem) {
        cancelOutstandingDetailPageTasks()
        itemPageCursors[item.id] = min(pageURLs(for: item).count, 1)
        requestedDetailPageURLs[item.id] = Set(pageURLs(for: item).prefix(1))
        pendingSelectionIndex = nil
        prefetchPageURL = nil
        loadedImageSlots = []
        appendSlots(for: item, pageOffset: 0, knownURLs: item.sampleImageURLs)
    }

    private func appendSlots(for item: GalleryItem, pageOffset: Int, knownURLs: [URL]) {
        let pageURLs = pageURLs(for: item)
        guard pageURLs.indices.contains(pageOffset) else { return }
        let currentCount = loadedImageSlots.count
        let pageURL = pageURLs[pageOffset]
        let count = max(knownURLs.count, 1)
        let newSlots = (0..<count).map { offset in
            ImageSlot(
                id: "\(item.id)-\(currentCount + offset + 1)",
                displayIndex: currentCount + offset + 1,
                pageURL: pageURL,
                pageImageIndex: offset,
                knownURL: knownURLs.indices.contains(offset) ? knownURLs[offset] : nil
            )
        }
        loadedImageSlots.append(contentsOf: newSlots)
    }

    private func applyPendingSelectionIfPossible() {
        guard let pendingSelectionIndex,
              loadedImageSlots.indices.contains(pendingSelectionIndex) else { return }
        selectedImageIndex = pendingSelectionIndex
        self.pendingSelectionIndex = nil
    }

    private func appendResolvedSlots(for item: GalleryItem, page: ResolvedImagePage) {
        let currentCount = loadedImageSlots.count
        let newSlots = page.imageURLs.enumerated().map { offset, imageURL in
            ImageSlot(
                id: "\(item.id)-\(currentCount + offset + 1)",
                displayIndex: currentCount + offset + 1,
                pageURL: page.pageURL,
                pageImageIndex: offset,
                knownURL: imageURL
            )
        }
        loadedImageSlots.append(contentsOf: newSlots)
    }

    private func resolveDetailPage(_ pageURL: URL) {
        let key = pageURL.absoluteString
        guard detailPageTasks[key] == nil else { return }
        detailPageTasks[key] = Task { [weak self] in
            do {
                let page = try await DetailPageHTMLResolver.resolve(pageURL: pageURL)
                guard !Task.isCancelled else { return }
                self?.registerResolvedPage(page)
            } catch {
                guard !Task.isCancelled else { return }
                self?.markDetailPageResolutionFailed(pageURL)
            }
        }
    }

    private func markDetailPageResolutionFailed(_ pageURL: URL) {
        detailPageTasks[pageURL.absoluteString] = nil
        if prefetchPageURL == pageURL {
            prefetchPageURL = nil
        }
        // 失败时清掉 requestedDetailPageURLs，让下次 ensureNext 仍有机会重试这条；
        // cursor 不回滚 —— 不死磕，但 chainLoad 会继续往后接力。
        for itemID in requestedDetailPageURLs.keys {
            requestedDetailPageURLs[itemID]?.remove(pageURL)
        }
        chainLoadIfNeeded()
    }

    private func cancelOutstandingDetailPageTasks() {
        detailPageTasks.values.forEach { $0.cancel() }
        detailPageTasks.removeAll()
    }

    private func pageURLs(for item: GalleryItem) -> [URL] {
        resolvedPageURLs[item.id] ?? item.pageURLs
    }

    private func mergeResolvedPageURLs(_ pageURLs: [URL], for item: GalleryItem) {
        guard !pageURLs.isEmpty else { return }
        var merged = self.pageURLs(for: item)
        for pageURL in pageURLs where !merged.contains(pageURL) {
            merged.append(pageURL)
        }
        resolvedPageURLs[item.id] = merged.sorted { lhs, rhs in
            pageNumber(lhs, detailURL: item.detailURL) < pageNumber(rhs, detailURL: item.detailURL)
        }
    }

    private func pageNumber(_ url: URL, detailURL: URL) -> Int {
        let detailPath = detailURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path != detailPath else { return 1 }
        return Int(path.split(separator: "/").last ?? "") ?? 1
    }

}

enum DetailPageLoadReason {
    case approachingLoadedEnd
    case filmstripReachedEnd
    case selectedBeyondLoadedRange
    case steppedPastLoadedRange
}
