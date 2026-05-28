import Foundation
import Observation

@MainActor
@Observable
final class MissKonDetailStore {
    var currentItem: MissKonItem?
    var imageSlots: [MissKonImageSlot] = []
    var selectedSlotID: MissKonImageSlot.ID?
    var isResolving = false
    var isResolutionComplete = false
    var errorMessage: String?

    private var resolvedPages: [URL: MissKonResolvedImagePage] = [:]
    private var failedPageURLs = Set<URL>()
    /// All page URLs discovered so far (initial + discovered via page.pageURLs).
    private var knownPageURLs: [URL] = []
    /// Per-page in-flight tasks.
    private var pageTasks: [URL: Task<Void, Never>] = [:]

    // MARK: - Cancel

    private func cancelAllPageTasks() {
        for task in pageTasks.values { task.cancel() }
        pageTasks.removeAll()
        isResolving = false
    }

    func cancelResolution() {
        cancelAllPageTasks()
    }

    var resolvedPageCount: Int { resolvedPages.count }
    var resolvedImageCount: Int {
        resolvedPages.reduce(0) { $0 + $1.value.imageURLs.count }
    }

    func imageURL(for slot: MissKonImageSlot) -> URL? {
        if let knownURL = slot.knownURL { return knownURL }
        return resolvedPages[slot.pageURL]?.imageURLs.element(at: slot.pageImageIndex)
    }

    // MARK: - Prepare

    func prepare(item: MissKonItem) {
        guard item.id != currentItem?.id else { return }
        cancelAllPageTasks()
        resolvedPages = [:]
        failedPageURLs = []
        isResolving = false
        isResolutionComplete = false
        errorMessage = nil
        imageSlots = []
        selectedSlotID = nil

        currentItem = item
        knownPageURLs = item.pageURLs
        guard !knownPageURLs.isEmpty else { return }

        // Generate placeholder slots based on imageCount, falling back to page estimate.
        let estimatedCount = item.imageCount > 0 ? item.imageCount : knownPageURLs.count * 12
        var slots: [MissKonImageSlot] = []
        for globalIndex in 0..<max(estimatedCount, 1) {
            let pageIndex = min(globalIndex / 12, knownPageURLs.count - 1)
            let imageInPage = globalIndex % 12
            let pageURL = knownPageURLs[pageIndex]
            let slot = MissKonImageSlot(
                id: "\(item.id)-p\(pageIndex)-i\(imageInPage)",
                displayIndex: globalIndex,
                pageURL: pageURL,
                pageImageIndex: imageInPage,
                knownURL: globalIndex == 0 ? item.coverURL : nil
            )
            slots.append(slot)
        }
        imageSlots = slots
        selectedSlotID = slots.first?.id
    }

    // MARK: - Progressive resolution

    /// Start resolving first page; prefetch next 2 pages when first completes.
    func resolve(item: MissKonItem, force: Bool = false) {
        guard force || item.id == currentItem?.id else { return }
        if force {
            cancelAllPageTasks()
            resolvedPages = [:]
            failedPageURLs = []
            errorMessage = nil
            isResolutionComplete = false
        } else {
            guard pageTasks.isEmpty, !isResolutionComplete else { return }
        }
        guard !knownPageURLs.isEmpty else { return }
        isResolving = true
        loadPage(knownPageURLs[0], prefetchNext: 2)
    }

    /// User navigated to a slot — load its page if not yet resolved.
    func ensurePageLoadedForSlot(at displayIndex: Int) {
        guard !isResolutionComplete,
              imageSlots.indices.contains(displayIndex) else { return }
        let slot = imageSlots[displayIndex]
        guard slot.knownURL == nil else { return }
        guard !resolvedPages.keys.contains(slot.pageURL),
              !failedPageURLs.contains(slot.pageURL) else { return }
        loadPage(slot.pageURL, prefetchNext: 0)
        // Also trigger threshold check.
        ensureNextDetailPageLoadedIfApproachingEnd(from: displayIndex)
    }

    /// Called when user navigates near the end of resolved slots.
    func ensureNextDetailPageLoadedIfApproachingEnd(from index: Int) {
        guard !isResolutionComplete else { return }
        // Use maxResolvedDisplayIndex (last slot with knownURL), not total slot count.
        let maxResolved = imageSlots.lastIndex(where: { $0.knownURL != nil }) ?? 0
        guard index >= max(maxResolved - 4, 0) else { return }
        loadNextUnresolvedPage()
    }

    /// Load the next unresolved page.
    func ensureNextDetailPageLoaded() {
        loadNextUnresolvedPage()
    }

    // MARK: - Page loading

    private func loadPage(_ pageURL: URL, prefetchNext: Int) {
        guard !isResolutionComplete else { return }
        guard !pageTasks.keys.contains(pageURL),
              !resolvedPages.keys.contains(pageURL),
              !failedPageURLs.contains(pageURL) else {
            // Already loading/resolved/failed — but still trigger prefetch if requested.
            if prefetchNext > 0 { schedulePrefetch(count: prefetchNext, after: pageURL) }
            return
        }

        pageTasks[pageURL] = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await MissKonDetailResolver.resolve(pageURL: pageURL)
                guard !Task.isCancelled, self.pageTasks[pageURL] != nil else { return }
                self.resolvedPages[pageURL] = page
                // Merge discovered page URLs into knownPageURLs.
                for newURL in page.pageURLs where !self.knownPageURLs.contains(newURL) {
                    self.knownPageURLs.append(newURL)
                }
                self.pageTasks[pageURL] = nil
                self.mergeResolvedPage(page, pageURL: pageURL)
                if prefetchNext > 0 {
                    self.schedulePrefetch(count: prefetchNext, after: pageURL)
                }
                self.checkCompletion()
            } catch {
                guard !Task.isCancelled else { return }
                self.pageTasks[pageURL] = nil
                self.failedPageURLs.insert(pageURL)
                self.checkCompletion()
            }
        }
        if pageTasks.count == 1 { isResolving = true }
    }

    private func loadNextUnresolvedPage() {
        guard !isResolutionComplete else { return }
        guard let nextURL = knownPageURLs.first(where: {
            !resolvedPages.keys.contains($0)
            && !failedPageURLs.contains($0)
            && !pageTasks.keys.contains($0)
        }) else { return }
        loadPage(nextURL, prefetchNext: 0)
    }

    private func schedulePrefetch(count: Int, after pageURL: URL) {
        // Find next unresolved pages in knownPageURLs after the given pageURL.
        guard let startIdx = knownPageURLs.firstIndex(of: pageURL) else { return }
        var loaded = 0
        for idx in (startIdx + 1)..<knownPageURLs.count {
            guard loaded < count else { break }
            let candidate = knownPageURLs[idx]
            guard !resolvedPages.keys.contains(candidate),
                  !failedPageURLs.contains(candidate),
                  !pageTasks.keys.contains(candidate) else { continue }
            loadPage(candidate, prefetchNext: 0)
            loaded += 1
        }
    }

    private func checkCompletion() {
        let allResolvedOrFailed = knownPageURLs.allSatisfy {
            resolvedPages.keys.contains($0) || failedPageURLs.contains($0)
        }
        if allResolvedOrFailed && pageTasks.isEmpty {
            isResolutionComplete = true
            isResolving = false
            if resolvedPages.isEmpty {
                errorMessage = "无法解析任何图片"
            }
        } else if pageTasks.isEmpty {
            isResolving = false
        }
    }

    // MARK: - Slot management

    /// Merge a resolved page's imageURLs into placeholder slots.
    private func mergeResolvedPage(_ page: MissKonResolvedImagePage, pageURL: URL) {
        guard let item = currentItem else { return }
        var slots = imageSlots
        // Update placeholder slots that belong to this page with real URLs.
        for i in slots.indices where slots[i].pageURL == pageURL {
            let imageIndex = slots[i].pageImageIndex
            if let realURL = page.imageURLs.element(at: imageIndex) {
                slots[i] = MissKonImageSlot(
                    id: slots[i].id,
                    displayIndex: slots[i].displayIndex,
                    pageURL: pageURL,
                    pageImageIndex: imageIndex,
                    knownURL: realURL
                )
            }
        }
        // If page provided URLs beyond our placeholder count, append new slots.
        let existingInPage = slots.filter { $0.pageURL == pageURL }.count
        if page.imageURLs.count > existingInPage {
            let baseDisplayIndex = slots.count
            for offset in existingInPage..<page.imageURLs.count {
                slots.append(MissKonImageSlot(
                    id: "\(item.id)-pExtra-\(pageURL.absoluteString.hashValue)-\(offset)",
                    displayIndex: baseDisplayIndex + (offset - existingInPage),
                    pageURL: pageURL,
                    pageImageIndex: offset,
                    knownURL: page.imageURLs[offset]
                ))
            }
        }
        // Re-index display indices.
        for i in slots.indices { slots[i] = MissKonImageSlot(
            id: slots[i].id,
            displayIndex: i,
            pageURL: slots[i].pageURL,
            pageImageIndex: slots[i].pageImageIndex,
            knownURL: slots[i].knownURL
        )}
        imageSlots = slots
        errorMessage = nil
        // Maintain selection across merges.
        if selectedSlotID == nil || !slots.contains(where: { $0.id == selectedSlotID }) {
            selectedSlotID = slots.first?.id
        }
    }

    // MARK: - Remaining

    func clear() {
        cancelAllPageTasks()
        currentItem = nil
        imageSlots = []
        selectedSlotID = nil
        isResolving = false
        errorMessage = nil
        resolvedPages = [:]
        failedPageURLs = []
        knownPageURLs = []
    }

    func retry() {
        guard let item = currentItem else { return }
        resolve(item: item, force: true)
    }

    func selectSlot(id: MissKonImageSlot.ID) {
        guard imageSlots.contains(where: { $0.id == id }) else { return }
        selectedSlotID = id
    }

    func selectSlot(at displayIndex: Int) {
        guard imageSlots.indices.contains(displayIndex) else { return }
        selectedSlotID = imageSlots[displayIndex].id
    }
}

private extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
