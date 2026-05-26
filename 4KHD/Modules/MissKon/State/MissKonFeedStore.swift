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
    private var searchTask: Task<Void, Never>?

    /// Per-section cache preserves items across section switches.
    private var cachedItems: [MissKonSection: [MissKonItem]] = [:]
    private var cachedNextPageURLs: [MissKonSection: URL] = [:]
    private var cacheTimestamps: [MissKonSection: Date] = [:]

    /// Auto-refresh cache if older than this interval.
    private static let cacheMaxAge: TimeInterval = 3600 // 1 hour

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
    }

    // MARK: - Cache Persistence

    private func saveCache() {
        guard let fileURL = Self.cacheFileURL else { return }
        let snapshot = CacheSnapshot(
            items: cachedItems.mapKeys { $0.rawValue },
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
        guard section.isNetworkBacked else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            do {
                let page = try await MissKonListResolver.resolve(section: self.section)
                guard !Task.isCancelled else { return }
                let existing = self.cachedItems[self.section] ?? []
                let existingIDs = Set(existing.map(\.id))
                let newItems = page.items.filter { !existingIDs.contains($0.id) }
                let merged = existing + newItems
                self.cachedItems[self.section] = merged
                self.allItems = merged
                self.visibleItems = merged
                self.nextPageURL = page.nextPageURL
                self.cachedNextPageURLs[self.section] = page.nextPageURL
                self.canLoadMoreList = page.nextPageURL != nil
                self.feedErrorMessage = nil
                self.cacheTimestamps[self.section] = Date()
                self.saveCacheIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            self.isRefreshingList = false
        }
    }

    func loadMoreListIfNeeded() {
        if activeSearchQuery != nil {
            loadMoreSearchIfNeeded()
            return
        }
        guard !isRefreshingList, canLoadMoreList else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self, let url = self.nextPageURL else { return }
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            do {
                let page = try await MissKonListResolver.resolve(pageURL: url, section: self.section)
                guard !Task.isCancelled else { return }
                var existing = self.cachedItems[self.section] ?? []
                let existingIDs = Set(existing.map(\.id))
                let newItems = page.items.filter { !existingIDs.contains($0.id) }
                existing.append(contentsOf: newItems)
                self.cachedItems[self.section] = existing
                self.allItems = existing
                self.visibleItems = existing
                self.nextPageURL = page.nextPageURL
                self.cachedNextPageURLs[self.section] = page.nextPageURL
                self.canLoadMoreList = page.nextPageURL != nil
                self.feedErrorMessage = nil
                self.cacheTimestamps[self.section] = Date()
                self.saveCacheIfNeeded()
            } catch {
                guard !Task.isCancelled else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            self.isRefreshingList = false
        }
    }

    func loadMoreSearchIfNeeded() {
        guard !isRefreshingList, canLoadMoreList, activeSearchQuery != nil else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self, let url = self.nextSearchPageURL else { return }
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            do {
                let page = try await MissKonListResolver.resolveSearch(pageURL: url)
                guard !Task.isCancelled else { return }
                var existingIDs = Set(self.allItems.map(\.id))
                let newItems = page.items.filter { existingIDs.insert($0.id).inserted }
                self.allItems.append(contentsOf: newItems)
                self.visibleItems = self.allItems
                self.nextSearchPageURL = page.nextPageURL
                self.canLoadMoreList = page.nextPageURL != nil
                self.feedErrorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            self.isRefreshingList = false
        }
    }

    func submitSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != activeSearchQuery else { return }
        loadTask?.cancel()
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            self.activeSearchQuery = trimmed
            self.isRefreshingList = true
            self.feedErrorMessage = nil
            do {
                let page = try await MissKonListResolver.resolveSearch(query: trimmed)
                guard !Task.isCancelled else { return }
                self.allItems = page.items
                self.visibleItems = page.items
                self.nextSearchPageURL = page.nextPageURL
                self.canLoadMoreList = page.nextPageURL != nil
                self.feedErrorMessage = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.feedErrorMessage = error.localizedDescription
            }
            self.isRefreshingList = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeSearchQuery = nil
        searchText = ""
        nextSearchPageURL = nil
        canLoadMoreList = false
        restoreSectionCache()
    }

    func select(_ item: MissKonItem) {
        selectedItemID = item.id
    }

    // MARK: - Private

    private func onSectionChanged() {
        searchTask?.cancel()
        searchTask = nil
        loadTask?.cancel()
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
            if selectedItemID == nil || !items.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = items.first?.id
            }
            return
        }
        if let cached = cachedItems[self.section], !cached.isEmpty {
            allItems = cached
            visibleItems = cached
            nextPageURL = cachedNextPageURLs[self.section]
            canLoadMoreList = nextPageURL != nil
            feedErrorMessage = nil
            if selectedItemID == nil || !cached.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = cached.first?.id
            }
            // Auto-refresh if cache is older than the max age
            if let timestamp = cacheTimestamps[self.section],
               Date().timeIntervalSince(timestamp) > Self.cacheMaxAge {
                refreshFromNetwork()
            }
        } else {
            allItems = []
            visibleItems = []
            selectedItemID = nil
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
