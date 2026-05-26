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
                self.allItems = page.items
                self.visibleItems = page.items
                self.nextPageURL = page.nextPageURL
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
        guard !isRefreshingList, canLoadMoreList, activeSearchQuery == nil else { return }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self, let url = self.nextPageURL else { return }
            self.isRefreshingList = true
            do {
                let page = try await MissKonListResolver.resolve(pageURL: url, section: self.section)
                guard !Task.isCancelled else { return }
                self.allItems.append(contentsOf: page.items)
                self.visibleItems = self.allItems
                self.nextPageURL = page.nextPageURL
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
            do {
                let page = try await MissKonListResolver.resolveSearch(pageURL: url)
                guard !Task.isCancelled else { return }
                self.allItems.append(contentsOf: page.items)
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
        refreshFromNetwork()
    }

    func select(_ item: MissKonItem) {
        selectedItemID = item.id
    }

    private func onSectionChanged() {
        refreshFromNetwork()
    }
}
