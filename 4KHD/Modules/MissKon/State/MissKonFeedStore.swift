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

    /// Per-section scroll offset for restoring position across section switches.
    var cachedScrollOffsets: [MissKonSection: CGFloat] = [:]

    /// Per-section cache preserves items across section switches.
    private var cachedItems: [MissKonSection: [MissKonItem]] = [:]
    private var cachedNextPageURLs: [MissKonSection: URL] = [:]
    private var cacheTimestamps: [MissKonSection: Date] = [:]

    /// Auto-refresh cache if older than this interval.
    private static let cacheMaxAge: TimeInterval = 3600 // 1 hour

    /// Called when the selected item changes, so the detail store can stay in sync.
    @ObservationIgnored var onSelectionChanged: ((MissKonItem?) -> Void)?

    private let favoritesStore: FavoritesStore

    private static var cacheDirectory: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("4KHD/MissKon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var cacheFileURL: URL? {
        cacheDirectory?.appendingPathComponent("feed-cache.json")
    }

    init(favoritesStore: FavoritesStore) {
        self.favoritesStore = favoritesStore
        loadCache()
        restoreSectionCache()
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
            timestamps: cacheTimestamps.mapKeys { $0.rawValue }.mapValues { $0.timeIntervalSince1970 }
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    private func loadCache() {
        guard let fileURL = Self.cacheFileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(CacheSnapshot.self, from: data) else { return }
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
    }

    private func saveCacheIfNeeded() {
        saveCache()
    }

    // MARK: - Network

    func refreshFromNetwork() {
        if !section.isNetworkBacked {
            if section == .favorites { restoreSectionCache() }
            return
        }
        if let query = activeSearchQuery, !query.isEmpty {
            submitSearch(query, force: true)
            return
        }
        let requestSection = section
        isRefreshingList = true
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
                self.saveCacheIfNeeded()
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
            }
        }
    }

    func loadMoreListIfNeeded() {
        if activeSearchQuery != nil {
            loadMoreSearchIfNeeded()
            return
        }
        guard !isRefreshingList, canLoadMoreList, let requestURL = nextPageURL else { return }
        guard inFlightPageURL != requestURL else { return } // Already loading this page.
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
                self.saveCacheIfNeeded()
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
                    self.feedErrorMessage = error.localizedDescription
                }
            }
            if self.section == requestSection {
                self.isRefreshingList = false
                self.loadTask = nil
                self.inFlightPageURL = nil
            }
        }
    }

    func loadMoreSearchIfNeeded() {
        guard !isRefreshingList, canLoadMoreList, activeSearchQuery != nil else { return }
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
                    self.feedErrorMessage = error.localizedDescription
                }
            }
            if self.activeSearchQuery == requestQuery {
                self.isRefreshingList = false
                self.searchLoadTask = nil
                self.inFlightSearchPageURL = nil
            }
        }
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
        activeSearchQuery = nil
        searchText = ""
        nextSearchPageURL = nil
        restoreSectionCache()
    }

    func restoreSectionCache() {
        if section == .favorites {
            let items = MissKonFavoritesBridge.missKonItems(from: favoritesStore.favorites)
            allItems = items
            visibleItems = items
            nextPageURL = nil
            canLoadMoreList = false
            feedErrorMessage = nil
            let previousID = selectedItemID
            if selectedItemID == nil || !items.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = items.first?.id
            }
            if selectedItemID != previousID {
                onSelectionChanged?(selectedItemID.flatMap { id in items.first { $0.id == id } })
            }
            return
        }
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
            // Auto-refresh if cache is older than the max age
            if let timestamp = cacheTimestamps[self.section],
               Date().timeIntervalSince(timestamp) > Self.cacheMaxAge {
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
            refreshFromNetwork()
        }
    }
}

// MARK: - Cache Snapshot

private struct CacheSnapshot: Codable {
    let items: [String: [MissKonItem]]
    let nextPageURLs: [String: String]
    var timestamps: [String: TimeInterval]?
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
