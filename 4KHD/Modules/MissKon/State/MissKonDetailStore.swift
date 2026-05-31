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
        let cachedFirstPage = DetailPageImageCache.shared.page(for: knownPageURLs[0]).map {
            MissKonResolvedImagePage(pageURL: $0.pageURL, imageURLs: $0.imageURLs, pageURLs: $0.pageURLs)
        }
        if let cachedFirstPage {
            resolvedPages[cachedFirstPage.pageURL] = cachedFirstPage
            reconcileKnownPageURLs(with: cachedFirstPage.pageURLs, requestedPageURL: cachedFirstPage.pageURL)
        }

        // When imageCount==0 we can't trust pageCount, so seed a safe minimum.
        if item.imageCount == 0, knownPageURLs.count == 1 {
            let base = knownPageURLs[0].absoluteString
            let baseWithSlash = base.hasSuffix("/") ? base : base + "/"
            for pageNum in 2...8 {
                guard let u = URL(string: "\(baseWithSlash)\(pageNum)/") else { break }
                knownPageURLs.append(u)
            }
        }

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
                knownURL: cachedFirstPage?.imageURLs.element(at: globalIndex) ?? (globalIndex == 0 ? item.coverURL : nil)
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
        // Only prefetch if first page hasn't been resolved yet.
        let firstResolved = resolvedPages.keys.contains(knownPageURLs[0])
        loadPage(knownPageURLs[0], prefetchNext: firstResolved ? 0 : 2)
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

        let itemID = currentItem?.id
        pageTasks[pageURL] = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await MissKonDetailResolver.resolve(pageURL: pageURL)
                guard !Task.isCancelled,
                      self.currentItem?.id == itemID,
                      self.pageTasks[pageURL] != nil
                else { return }
                self.reconcileKnownPageURLs(with: page.pageURLs, requestedPageURL: pageURL)
                self.resolvedPages[pageURL] = page
                self.pageTasks[pageURL] = nil
                self.mergeResolvedPage(page, pageURL: pageURL)
                if prefetchNext > 0 {
                    self.schedulePrefetch(count: prefetchNext, after: pageURL)
                }
                self.checkCompletion()
            } catch {
                guard !Task.isCancelled,
                      self.currentItem?.id == itemID,
                      self.pageTasks[pageURL] != nil
                else { return }
                self.pageTasks[pageURL] = nil
                self.failedPageURLs.insert(pageURL)
                self.removeSlots(forFailedPage: pageURL)
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

    private func reconcileKnownPageURLs(with resolvedPageURLs: [URL], requestedPageURL: URL) {
        guard !resolvedPageURLs.isEmpty else { return }
        let normalized = orderedDetailPageURLs(resolvedPageURLs)
        guard normalized.contains(requestedPageURL) else { return }

        let resolvedSet = Set(normalized)
        let removedPageURLs = knownPageURLs.filter { !resolvedSet.contains($0) }
        guard !removedPageURLs.isEmpty || normalized != knownPageURLs else { return }

        for pageURL in removedPageURLs {
            pageTasks[pageURL]?.cancel()
            pageTasks[pageURL] = nil
            resolvedPages[pageURL] = nil
            failedPageURLs.remove(pageURL)
        }

        knownPageURLs = normalized
        pruneSlots(excluding: removedPageURLs)
    }

    private func orderedDetailPageURLs(_ pageURLs: [URL]) -> [URL] {
        var seen = Set<URL>()
        return pageURLs
            .filter { seen.insert($0).inserted }
            .sorted { lhs, rhs in
                pageOrder(lhs) < pageOrder(rhs)
            }
    }

    private func pageOrder(_ url: URL) -> Int {
        url.trailingPageNumber ?? 1
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

    /// Merge a resolved page: replace all slots for this pageURL with exact imageURLs.
    private func mergeResolvedPage(_ page: MissKonResolvedImagePage, pageURL: URL) {
        guard let item = currentItem else { return }
        let pageSlots: [MissKonImageSlot] = page.imageURLs.enumerated().map { offset, imageURL in
            MissKonImageSlot(
                id: "\(item.id)-p-\(pageURL.absoluteString.hashValue)-\(offset)",
                displayIndex: 0,
                pageURL: pageURL,
                pageImageIndex: offset,
                knownURL: imageURL
            )
        }
        replaceSlots(for: pageURL, with: pageSlots)
        errorMessage = nil
    }

    /// Remove placeholder slots for a page that failed to resolve.
    private func removeSlots(forFailedPage pageURL: URL) {
        replaceSlots(for: pageURL, with: [])
    }

    private func pruneSlots(excluding removedPageURLs: [URL]) {
        guard !removedPageURLs.isEmpty else { return }
        let removedSet = Set(removedPageURLs)
        var slots = imageSlots.filter { !removedSet.contains($0.pageURL) }
        reindex(&slots)
        imageSlots = slots
        if let selectedSlotID, slots.contains(where: { $0.id == selectedSlotID }) { return }
        selectedSlotID = slots.first?.id
    }

    /// Replace all slots for `pageURL` with `newSlots` (empty = remove), then reindex + repair selection.
    private func replaceSlots(for pageURL: URL, with pageSlots: [MissKonImageSlot]) {
        let slots = imageSlots
        let selectedSlot = selectedSlotID.flatMap { id in slots.first(where: { $0.id == id }) }
        let selectedIndex = selectedSlot.flatMap { s in slots.firstIndex(where: { $0.id == s.id }) }

        // Filter out all slots for this pageURL.
        let keepIndices = slots.indices.filter { slots[$0].pageURL != pageURL }
        var newSlots = keepIndices.map { slots[$0] }

        if !pageSlots.isEmpty {
            // Insert after the last slot whose pageURL comes before `pageURL` in knownPageURLs.
            guard let pageOrder = knownPageURLs.firstIndex(of: pageURL) else { return }
            let insertAt = newSlots.firstIndex { slot in
                guard let order = knownPageURLs.firstIndex(of: slot.pageURL) else { return false }
                return order > pageOrder
            } ?? newSlots.count
            newSlots.insert(contentsOf: pageSlots, at: insertAt)
        }

        reindex(&newSlots)
        imageSlots = newSlots

        // Repair selection.
        if let id = selectedSlotID, newSlots.contains(where: { $0.id == id }) { return }
        if let idx = selectedIndex {
            let target = min(idx, newSlots.count - 1)
            if target >= 0 { selectedSlotID = newSlots[target].id; return }
        }
        selectedSlotID = newSlots.first?.id
    }

    private func reindex(_ slots: inout [MissKonImageSlot]) {
        for i in slots.indices {
            slots[i] = MissKonImageSlot(
                id: slots[i].id,
                displayIndex: i,
                pageURL: slots[i].pageURL,
                pageImageIndex: slots[i].pageImageIndex,
                knownURL: slots[i].knownURL
            )
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
