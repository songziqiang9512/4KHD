import Foundation
import Observation

@MainActor
@Observable
final class MissKonFeedStore {
    var section: MissKonSection = .latest { didSet { onSectionChanged() } }
    var visibleItems: [MissKonItem] = []
    var allItems: [MissKonItem] = []
    var selectedItemID: MissKonItem.ID?
    var isRefreshingList = false
    var canLoadMoreList = false
    var feedErrorMessage: String?

    var searchText = ""
    var activeSearchQuery: String?

    private var nextPageURL: URL?
    private var nextSearchPageURL: URL?
    private var loadTask: Task<Void, Never>?
    private var searchLoadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    /// In-flight page URL to prevent duplicate load-more requests.
    private var inFlightPageURL: URL?
    private var inFlightSearchPageURL: URL?
    private var pendingListLoadMore = false
    private var pendingSearchLoadMore = false

    /// Per-section scroll offset for restoring position across section switches.
    var cachedScrollOffsets: [MissKonSection: CGFloat] = [:]

    /// Per-section cache preserves items across section switches.
    private var cachedItems: [MissKonSection: [MissKonItem]] = [:]
    private var cachedNextPageURLs: [MissKonSection: URL] = [:]
    private var cacheTimestamps: [MissKonSection: Date] = [:]
    /// 已确认翻到最后一页的板块：cachedNextPageURLs 为 nil 时不再误判为“分页链断裂”而重拉第 1 页。
    private var noMorePagesSections: Set<MissKonSection> = []
    @ObservationIgnored private var cacheLoadTask: Task<Void, Never>?
    @ObservationIgnored private var didLoadCache = false
    @ObservationIgnored private var pendingNetworkRefresh = false
    @ObservationIgnored private let cacheWriteQueue = DispatchQueue(
        label: "com.songziqiang.4khd.misskon-cache",
        qos: .utility
    )

    private static let fullPageItemCount = 20

    /// Auto-refresh cache if older than this interval.
    private static let cacheMaxAge: TimeInterval = 3600 // 1 hour

    /// Called when the selected item changes, so the detail store can stay in sync.
    @ObservationIgnored var onSelectionChanged: ((MissKonItem?) -> Void)?

    private static var cacheDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return appSupport.appendingPathComponent("4KHD/MissKon", isDirectory: true)
    }

    private static var cacheFileURL: URL? {
        cacheDirectory?.appendingPathComponent("feed-cache.json")
    }

    init() {
        let cacheFileURL = Self.cacheFileURL
        cacheLoadTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                Self.loadCacheSnapshot(from: cacheFileURL)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.applyCacheSnapshot(snapshot)
            self.didLoadCache = true
            self.cacheLoadTask = nil
            self.restoreSectionCache(allowNetworkRefresh: false)
            if self.pendingNetworkRefresh {
                self.pendingNetworkRefresh = false
                self.refreshFromNetwork()
            }
        }
    }

    // MARK: - Cache Persistence

    private static let maxCachedItemsPerSection = 200

    private func saveCache() {
        guard let fileURL = Self.cacheFileURL else { return }
        // Trim each section to max items before persisting.
        var trimmedItems: [MissKonSection: [MissKonItem]] = [:]
        for (section, items) in cachedItems {
            trimmedItems[section] = items.count > Self.maxCachedItemsPerSection
                ? Array(items.prefix(Self.maxCachedItemsPerSection))
                : items
        }
        let snapshot = CacheSnapshot(
            items: trimmedItems.mapKeys { $0.rawValue },
            nextPageURLs: cachedNextPageURLs.mapKeys { $0.rawValue }.mapValues { $0.absoluteString },
            timestamps: cacheTimestamps.mapKeys { $0.rawValue }.mapValues { $0.timeIntervalSince1970 },
            noMorePages: Dictionary(uniqueKeysWithValues: noMorePagesSections.map { ($0.rawValue, true) })
        )
        cacheWriteQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomicWrite)
            } catch {
                // A failed cache write must not affect the live feed.
            }
        }
    }

    private nonisolated static func loadCacheSnapshot(from fileURL: URL?) -> CacheSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(CacheSnapshot.self, from: data)
    }

    private func applyCacheSnapshot(_ snapshot: CacheSnapshot?) {
        guard let snapshot else { return }
        for (key, items) in snapshot.items {
            guard let section = MissKonSection(rawValue: key) else { continue }
            cachedItems[section] = items
        }
        for (key, urlString) in snapshot.nextPageURLs {
            guard let section = MissKonSection(rawValue: key),
                  let url = URL(string: urlString) else { continue }
            cachedNextPageURLs[section] = url
        }
        for (key, timestamp) in snapshot.timestamps ?? [:] {
            guard let section = MissKonSection(rawValue: key) else { continue }
            cacheTimestamps[section] = Date(timeIntervalSince1970: timestamp)
        }
        for (key, isAtEnd) in snapshot.noMorePages ?? [:] where isAtEnd {
            guard let section = MissKonSection(rawValue: key) else { continue }
            noMorePagesSections.insert(section)
        }
        if pruneStaleAIGeneratedNextPageIfNeeded() {
            saveCache()
        }
    }

    func clearCache() async throws {
        cacheLoadTask?.cancel()
        cacheLoadTask = nil
        didLoadCache = true
        pendingNetworkRefresh = false
        loadTask?.cancel()
        searchLoadTask?.cancel()
        searchTask?.cancel()
        searchDebounceTask?.cancel()
        loadTask = nil
        searchLoadTask = nil
        searchTask = nil
        searchDebounceTask = nil
        inFlightPageURL = nil
        inFlightSearchPageURL = nil
        pendingListLoadMore = false
        pendingSearchLoadMore = false
        isRefreshingList = false
        cachedItems.removeAll()
        cachedNextPageURLs.removeAll()
        cacheTimestamps.removeAll()
        noMorePagesSections.removeAll()
        let cacheDirectory = Self.cacheDirectory
        let cacheWriteQueue = cacheWriteQueue
        try await Task.detached(priority: .utility) {
            try cacheWriteQueue.sync {
                guard let cacheDirectory,
                      FileManager.default.fileExists(atPath: cacheDirectory.path) else {
                    return
                }
                try FileManager.default.removeItem(at: cacheDirectory)
            }
        }.value
    }

    // MARK: - Network

    func refreshFromNetwork() {
        guard didLoadCache else {
            pendingNetworkRefresh = true
            return
        }
        if let query = activeSearchQuery, !query.isEmpty {
            submitSearch(query, force: true)
            return
        }
        let requestSection = section
        isRefreshingList = true
        pendingListLoadMore = false
        inFlightPageURL = nil
        loadTask?.cancel()
        loadTask = nil
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.feedErrorMessage = nil
            do {
                let page = try await MissKonListResolver.resolve(section: requestSection)
                guard !Task.isCancelled else { return }
                let existing = self.cachedItems[requestSection] ?? []
                let pageIDs = Set(page.items.map(\.id))
                let keptExisting = existing.filter { !pageIDs.contains($0.id) }
                // Put newest page first; deduped old items follow.
                let merged = page.items + keptExisting
                self.cachedItems[requestSection] = merged
                self.cachedNextPageURLs[requestSection] = page.nextPageURL
                self.cacheTimestamps[requestSection] = Date()
                if page.nextPageURL == nil {
                    self.noMorePagesSections.insert(requestSection)
                } else {
                    self.noMorePagesSections.remove(requestSection)
                }
                self.saveCache()
                if self.section == requestSection, self.activeSearchQuery == nil {
                    self.allItems = merged
                    self.visibleItems = merged
                    self.nextPageURL = page.nextPageURL
                    self.canLoadMoreList = page.nextPageURL != nil
                    self.feedErrorMessage = nil
                    // Auto-select first item if nothing is selected (e.g., first launch)
                    if self.selectedItemID == nil || !merged.contains(where: { $0.id == self.selectedItemID }) {
                        let firstItem = merged.first
                        self.selectedItemID = firstItem?.id
                        self.onSelectionChanged?(firstItem)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                if self.section == requestSection {
                    self.feedErrorMessage = error.localizedDescription
                }
            }
            if self.section == requestSection {
                self.isRefreshingList = false
                self.loadTask = nil
                if self.pendingListLoadMore {
                    self.pendingListLoadMore = false
                    self.loadMoreListIfNeeded()
                }
            }
        }
    }

    func bootstrapIfNeeded() {
        guard loadTask == nil, !isRefreshingList else { return }
        refreshFromNetwork()
    }

    func loadMoreListIfNeeded() {
        if activeSearchQuery != nil {
            loadMoreSearchIfNeeded()
            return
        }
        guard canLoadMoreList, let requestURL = nextPageURL else { return }
        guard !isRefreshingList, loadTask == nil else {
            pendingListLoadMore = true
            return
        }
        guard inFlightPageURL != requestURL else { return }
        inFlightPageURL = requestURL
        let requestSection = section
        isRefreshingList = true
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.feedErrorMessage = nil
            do {
                let page = try await MissKonListResolver.resolve(pageURL: requestURL, section: requestSection)
                guard !Task.isCancelled else { return }
                var existing = self.cachedItems[requestSection] ?? []
                let existingIDs = Set(existing.map(\.id))
                let newItems = page.items.filter { !existingIDs.contains($0.id) }
                existing.append(contentsOf: newItems)
                self.cachedItems[requestSection] = existing
                self.cachedNextPageURLs[requestSection] = page.nextPageURL
                self.cacheTimestamps[requestSection] = Date()
                if page.nextPageURL == nil {
                    self.noMorePagesSections.insert(requestSection)
                } else {
                    self.noMorePagesSections.remove(requestSection)
                }
                self.saveCache()
                if self.section == requestSection, self.activeSearchQuery == nil {
                    self.allItems = existing
                    self.visibleItems = existing
                    self.nextPageURL = page.nextPageURL
                    self.canLoadMoreList = page.nextPageURL != nil
                    self.feedErrorMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                if self.section == requestSection {
                    if self.isTerminalLoadMoreError(error) {
                        self.markNoMorePages(for: requestSection)
                    } else {
                        self.feedErrorMessage = error.localizedDescription
                    }
                }
            }
            if self.section == requestSection {
                self.isRefreshingList = false
                self.loadTask = nil
                self.inFlightPageURL = nil
                if self.pendingListLoadMore {
                    self.pendingListLoadMore = false
                    self.loadMoreListIfNeeded()
                }
            }
        }
    }

    func loadMoreSearchIfNeeded() {
        guard canLoadMoreList, activeSearchQuery != nil else { return }
        guard !isRefreshingList, searchTask == nil, searchLoadTask == nil else {
            pendingSearchLoadMore = true
            return
        }
        let requestQuery = activeSearchQuery
        guard let requestURL = nextSearchPageURL else { return }
        guard inFlightSearchPageURL != requestURL else { return }
        inFlightSearchPageURL = requestURL
        isRefreshingList = true
        searchLoadTask?.cancel()
        searchLoadTask = Task { [weak self] in
            guard let self else { return }
            self.feedErrorMessage = nil
            do {
                let page = try await MissKonListResolver.resolveSearch(pageURL: requestURL)
                guard !Task.isCancelled, self.activeSearchQuery == requestQuery else { return }
                var existingIDs = Set(self.allItems.map(\.id))
                let newItems = page.items.filter { existingIDs.insert($0.id).inserted }
                self.allItems.append(contentsOf: newItems)
                self.visibleItems = self.allItems
                self.nextSearchPageURL = page.nextPageURL
                self.canLoadMoreList = page.nextPageURL != nil
                self.feedErrorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                if self.activeSearchQuery == requestQuery {
                    if self.isTerminalLoadMoreError(error) {
                        self.nextSearchPageURL = nil
                        self.canLoadMoreList = false
                        self.feedErrorMessage = nil
                        self.pendingSearchLoadMore = false
                    } else {
                        self.feedErrorMessage = error.localizedDescription
                    }
                }
            }
            if self.activeSearchQuery == requestQuery {
                self.isRefreshingList = false
                self.searchLoadTask = nil
                self.inFlightSearchPageURL = nil
                if self.pendingSearchLoadMore {
                    self.pendingSearchLoadMore = false
                    self.loadMoreSearchIfNeeded()
                }
            }
        }
    }

    private func markNoMorePages(for requestSection: MissKonSection) {
        cachedNextPageURLs[requestSection] = nil
        cacheTimestamps[requestSection] = Date()
        noMorePagesSections.insert(requestSection)
        saveCache()
        guard section == requestSection, activeSearchQuery == nil else { return }
        nextPageURL = nil
        canLoadMoreList = false
        feedErrorMessage = nil
        pendingListLoadMore = false
    }

    private func isTerminalLoadMoreError(_ error: Error) -> Bool {
        guard let resolverError = error as? MissKonListResolverError else { return false }
        return resolverError.isPageNotFound
    }

    func setSearchText(_ text: String) {
        searchText = text
        searchDebounceTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if activeSearchQuery != nil { clearSearch() }
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.submitSearch(trimmed)
        }
    }

    func submitSearch(_ query: String, force: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard force || trimmed != activeSearchQuery else { return }
        activeSearchQuery = trimmed
        isRefreshingList = true
        feedErrorMessage = nil
        nextSearchPageURL = nil
        inFlightSearchPageURL = nil
        pendingSearchLoadMore = false
        loadTask?.cancel()
        loadTask = nil
        searchTask?.cancel()
        searchTask = nil
        searchLoadTask?.cancel()
        searchLoadTask = nil
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await MissKonListResolver.resolveSearch(query: trimmed)
                guard !Task.isCancelled, self.activeSearchQuery == trimmed else { return }
                self.allItems = page.items
                self.visibleItems = page.items
                self.nextSearchPageURL = page.nextPageURL
                self.canLoadMoreList = page.nextPageURL != nil
                self.feedErrorMessage = nil
                let firstItem = page.items.first
                self.selectedItemID = firstItem?.id
                self.onSelectionChanged?(firstItem)
            } catch {
                guard !Task.isCancelled, self.activeSearchQuery == trimmed else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            if self.activeSearchQuery == trimmed {
                self.isRefreshingList = false
                self.searchTask = nil
            }
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchLoadTask?.cancel()
        searchLoadTask = nil
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        loadTask?.cancel()
        loadTask = nil
        activeSearchQuery = nil
        searchText = ""
        nextSearchPageURL = nil
        inFlightPageURL = nil
        inFlightSearchPageURL = nil
        pendingListLoadMore = false
        pendingSearchLoadMore = false
        canLoadMoreList = false
        isRefreshingList = false
        restoreSectionCache()
    }

    var selectedItem: MissKonItem? {
        guard let selectedItemID else { return nil }
        return allItems.first { $0.id == selectedItemID }
    }

    func select(_ item: MissKonItem) {
        guard selectedItemID != item.id else { return }
        selectedItemID = item.id
        onSelectionChanged?(item)
    }

    // MARK: - Private

    private func onSectionChanged() {
        searchTask?.cancel()
        searchTask = nil
        searchLoadTask?.cancel()
        searchLoadTask = nil
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        loadTask?.cancel()
        loadTask = nil
        isRefreshingList = false
        inFlightPageURL = nil
        inFlightSearchPageURL = nil
        pendingListLoadMore = false
        pendingSearchLoadMore = false
        activeSearchQuery = nil
        searchText = ""
        nextSearchPageURL = nil
        restoreSectionCache()
    }

    func restoreSectionCache(allowNetworkRefresh: Bool = true) {
        guard didLoadCache else { return }
        if let cached = cachedItems[self.section], !cached.isEmpty {
            allItems = cached
            visibleItems = cached
            nextPageURL = cachedNextPageURLs[self.section]
            canLoadMoreList = nextPageURL != nil
            feedErrorMessage = nil
            let previousID = selectedItemID
            if selectedItemID == nil || !cached.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = cached.first?.id
            }
            if selectedItemID != previousID {
                onSelectionChanged?(selectedItemID.flatMap { id in cached.first { $0.id == id } })
            }
            // Auto-refresh if cache is stale or missing nextPageURL (pagination chain broken).
            // 已到末尾的板块（noMorePagesSections）缺失 nextPageURL 属正常终态，不重拉第 1 页。
            let needsRefresh: Bool
            if cachedNextPageURLs[self.section] == nil,
               !noMorePagesSections.contains(self.section) {
                needsRefresh = true
            } else if let timestamp = cacheTimestamps[self.section],
                      Date().timeIntervalSince(timestamp) > Self.cacheMaxAge {
                needsRefresh = true
            } else {
                needsRefresh = false
            }
            if needsRefresh, allowNetworkRefresh {
                refreshFromNetwork()
            }
        } else {
            allItems = []
            visibleItems = []
            nextPageURL = nil
            let previousID = selectedItemID
            selectedItemID = nil
            if previousID != nil {
                onSelectionChanged?(nil)
            }
            feedErrorMessage = nil
            canLoadMoreList = false
            if allowNetworkRefresh {
                refreshFromNetwork()
            }
        }
    }

    private func pruneStaleAIGeneratedNextPageIfNeeded() -> Bool {
        let section = MissKonSection.aiGenerated
        guard let items = cachedItems[section],
              !items.isEmpty,
              items.count % Self.fullPageItemCount != 0,
              let nextPageURL = cachedNextPageURLs[section],
              pageNumber(from: nextPageURL) == cachedPageCount(for: items.count) + 1 else {
            return false
        }
        cachedNextPageURLs[section] = nil
        cacheTimestamps[section] = Date()
        return true
    }

    private func cachedPageCount(for itemCount: Int) -> Int {
        max(1, (itemCount + Self.fullPageItemCount - 1) / Self.fullPageItemCount)
    }

    private func pageNumber(from url: URL) -> Int? {
        let parts = url.path.split(separator: "/")
        guard let pageIndex = parts.firstIndex(of: "page") else { return nil }
        let numberIndex = parts.index(after: pageIndex)
        guard parts.indices.contains(numberIndex) else { return nil }
        return Int(parts[numberIndex])
    }
}

// MARK: - Cache Snapshot

nonisolated private struct CacheSnapshot: Codable {
    let items: [String: [MissKonItem]]
    let nextPageURLs: [String: String]
    var timestamps: [String: TimeInterval]?
    var noMorePages: [String: Bool]?
}

extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) -> T) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
}
