import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published var section: GallerySection = .latest {
        didSet {
            selectFirstItemIfNeeded(force: true)
            refreshFromNetwork()
        }
    }
    @Published var selectedItemID: GalleryItem.ID?
    @Published var selectedImageIndex = 0
    @Published private(set) var visibleCount = 18
    @Published private(set) var loadedImageSlots: [ImageSlot] = []
    @Published private(set) var prefetchPageURL: URL?
    @Published private(set) var isRefreshingList = false
    @Published var isFullscreenViewerPresented = false

    private var library = ApifyLibrary()
    private var favorites: [FavoriteGalleryItem] = []
    private var listRefreshTasks: [GallerySection: Task<Void, Never>] = [:]
    private var itemPageCursors: [GalleryItem.ID: Int] = [:]
    private var resolvedPageURLs: [GalleryItem.ID: [URL]] = [:]
    private var requestedDetailPageURLs: [GalleryItem.ID: Set<URL>] = [:]
    private var detailPageTasks: [String: Task<Void, Never>] = [:]
    private var pendingSelectionIndex: Int?
    private static let favoritesDefaultsKey = "com.songziqiang.4khd.favoriteItems.v1"

    init() {
        loadFavorites()
        selectFirstItemIfNeeded(force: true)
    }

    var allItems: [GalleryItem] {
        if section == .favorites {
            return favorites.compactMap(Self.favoriteToGalleryItem)
        }
        return library.items(in: section)
    }

    var visibleItems: [GalleryItem] {
        Array(allItems.prefix(visibleCount))
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
        visibleCount = min(visibleCount + 18, allItems.count)
    }

    func refreshFromNetwork() {
        guard section != .favorites else { return }
        let currentSection = section
        listRefreshTasks[currentSection]?.cancel()
        isRefreshingList = true
        listRefreshTasks[currentSection] = Task { [weak self] in
            do {
                let items = try await SiteListResolver.resolve(section: currentSection)
                await self?.applyNetworkItems(items, section: currentSection)
            } catch {
                await self?.finishListRefresh(section: currentSection)
            }
        }
    }

    private func applyNetworkItems(_ items: [GalleryItem], section: GallerySection) {
        guard !items.isEmpty else {
            finishListRefresh(section: section)
            return
        }
        let selectedID = selectedItemID
        let selectedURL = selectedSlot?.pageURL
        let selectedIndex = selectedImageIndex

        library = library.replacing(section: section, with: items)
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

    private func finishListRefresh(section: GallerySection) {
        listRefreshTasks[section] = nil
        if section == self.section {
            isRefreshingList = false
        }
    }

    func select(_ item: GalleryItem) {
        selectedItemID = item.id
        selectedImageIndex = 0
        rebuildInitialSlots(for: item)
    }

    func toggleFavorite(for item: GalleryItem) {
        if favorites.contains(where: { $0.detailURL == item.detailURL.absoluteString }) {
            favorites.removeAll { $0.detailURL == item.detailURL.absoluteString }
        } else {
            favorites.append(Self.galleryToFavorite(item))
        }
        saveFavorites()
        if section == .favorites {
            selectFirstItemIfNeeded(force: true)
        }
    }

    func isFavorite(_ item: GalleryItem) -> Bool {
        favorites.contains(where: { $0.detailURL == item.detailURL.absoluteString })
    }

    func selectImage(at index: Int) {
        guard index >= 0 else { return }
        if index >= loadedImageSlots.count {
            let oldCount = loadedImageSlots.count
            ensureNextDetailPageLoaded(reason: .selectedBeyondLoadedRange)
            if loadedImageSlots.indices.contains(oldCount) {
                selectedImageIndex = oldCount
                return
            }
            pendingSelectionIndex = oldCount
        }
        if loadedImageSlots.indices.contains(index) {
            selectedImageIndex = index
            ensureNextDetailPageLoadedIfApproachingEnd(from: index)
        }
    }

    func stepImage(_ delta: Int) {
        let nextIndex = selectedImageIndex + delta
        if delta > 0, nextIndex >= loadedImageSlots.count {
            ensureNextDetailPageLoaded(reason: .steppedPastLoadedRange)
        }
        selectImage(at: nextIndex)
    }

    func ensureNextDetailPageLoaded(reason: DetailPageLoadReason) {
        guard let item = selectedItem else { return }
        let cursor = itemPageCursors[item.id, default: 1]
        let pageURLs = pageURLs(for: item)
        guard cursor < pageURLs.count else { return }
        let pageURL = pageURLs[cursor]
        guard requestedDetailPageURLs[item.id, default: []].insert(pageURL).inserted else { return }
        itemPageCursors[item.id] = cursor + 1
        prefetchPageURL = pageURL
        resolveDetailPage(pageURL)
    }

    private func ensureNextDetailPageLoadedIfApproachingEnd(from index: Int) {
        guard loadedImageSlots.count - index <= 6 else { return }
        ensureNextDetailPageLoaded(reason: .approachingLoadedEnd)
    }

    func registerResolvedPage(_ page: ResolvedImagePage) {
        guard let item = selectedItem else { return }
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
            return
        }
        appendResolvedSlots(for: item, page: page)
        applyPendingSelectionIfPossible()
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
            select(first)
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: Self.favoritesDefaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteGalleryItem].self, from: data) else {
            favorites = []
            return
        }
        favorites = decoded
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
                await self?.registerResolvedPage(page)
            } catch {
                guard !Task.isCancelled else { return }
                await self?.markDetailPageResolutionFailed(pageURL)
            }
        }
    }

    private func markDetailPageResolutionFailed(_ pageURL: URL) {
        detailPageTasks[pageURL.absoluteString] = nil
        if prefetchPageURL == pageURL {
            prefetchPageURL = nil
        }
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
