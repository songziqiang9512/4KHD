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

    // MARK: - Network

    func refreshFromNetwork() {
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

    private func restoreSectionCache() {
        if let cached = cachedItems[self.section], !cached.isEmpty {
            allItems = cached
            visibleItems = cached
            nextPageURL = cachedNextPageURLs[self.section]
            canLoadMoreList = nextPageURL != nil
            feedErrorMessage = nil
            if selectedItemID == nil || !cached.contains(where: { $0.id == selectedItemID }) {
                selectedItemID = cached.first?.id
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
