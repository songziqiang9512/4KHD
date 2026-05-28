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
    private var resolveTask: Task<Void, Never>?
    private var inFlightPageURLs: Set<URL> = []

    private func cancelResolveTask() {
        resolveTask?.cancel()
        resolveTask = nil
        isResolving = false
        inFlightPageURLs.removeAll()
    }

    func cancelResolution() {
        resolveTask?.cancel()
        resolveTask = nil
        isResolving = false
        inFlightPageURLs.removeAll()
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
        cancelResolveTask()
        resolvedPages = [:]
        failedPageURLs = []
        isResolving = false
        isResolutionComplete = false
        errorMessage = nil
        imageSlots = []
        selectedSlotID = nil

        currentItem = item
        let pageURLs = item.pageURLs
        guard !pageURLs.isEmpty else { return }

        // Generate placeholder slots based on imageCount, falling back to page estimate.
        let estimatedCount = item.imageCount > 0 ? item.imageCount : pageURLs.count * 12
        var slots: [MissKonImageSlot] = []
        for globalIndex in 0..<max(estimatedCount, 1) {
            let pageIndex = min(globalIndex / 12, pageURLs.count - 1)
            let imageInPage = globalIndex % 12
            let pageURL = pageURLs[pageIndex]
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

    /// Start resolving — only first page eagerly. Further pages load on demand.
    func resolve(item: MissKonItem, force: Bool = false) {
        guard force || item.id == currentItem?.id else { return }
        if force {
            cancelResolveTask()
            resolvedPages = [:]
            failedPageURLs = []
            errorMessage = nil
            isResolutionComplete = false
        } else {
            guard resolveTask == nil, !isResolutionComplete else { return }
        }
        let pageURLs = item.pageURLs
        guard !pageURLs.isEmpty else { return }
        let itemID = item.id
        isResolving = true

        resolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.currentItem?.id == itemID {
                    self.isResolving = false
                    self.resolveTask = nil
                }
            }

            // Filter to pages not yet resolved/failed/in-flight.
            let pending = pageURLs.filter {
                !self.resolvedPages.keys.contains($0)
                && !self.failedPageURLs.contains($0)
                && !self.inFlightPageURLs.contains($0)
            }
            guard let firstURL = pending.first else {
                if self.resolvedPages.isEmpty {
                    self.errorMessage = "无法解析任何图片"
                } else {
                    self.isResolutionComplete = true
                }
                return
            }

            self.inFlightPageURLs.insert(firstURL)
            do {
                let page = try await MissKonDetailResolver.resolve(pageURL: firstURL)
                guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
                self.resolvedPages[firstURL] = page
                self.inFlightPageURLs.remove(firstURL)
                self.mergeResolvedPage(page, pageURL: firstURL)
            } catch {
                self.inFlightPageURLs.remove(firstURL)
                self.failedPageURLs.insert(firstURL)
            }

            // Check if that single page covers all — for single-page items, mark complete.
            if self.resolvedPages.count >= pageURLs.count
                || self.resolvedPages.values.reduce(0, { $0 + $1.imageURLs.count }) >= self.imageSlots.count {
                self.isResolutionComplete = true
            }
        }
    }

    /// Called when user navigates near the end of loaded slots.
    func ensureNextDetailPageLoadedIfApproachingEnd(from index: Int) {
        guard !isResolutionComplete, !isResolving else { return }
        let threshold = imageSlots.count - 4
        guard index >= max(threshold, 0) else { return }
        ensureNextDetailPageLoaded()
    }

    /// Load the next unresolved page.
    func ensureNextDetailPageLoaded() {
        guard let item = currentItem, !isResolutionComplete else { return }
        let pageURLs = item.pageURLs
        // Find the first page not yet resolved, failed, or in-flight.
        guard let nextURL = pageURLs.first(where: {
            !resolvedPages.keys.contains($0)
            && !failedPageURLs.contains($0)
            && !inFlightPageURLs.contains($0)
        }) else {
            if resolvedPages.count >= pageURLs.count {
                isResolutionComplete = true
            }
            return
        }

        inFlightPageURLs.insert(nextURL)
        isResolving = true
        let itemID = item.id
        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.currentItem?.id == itemID {
                    self.isResolving = false
                    self.resolveTask = nil
                }
            }
            do {
                let page = try await MissKonDetailResolver.resolve(pageURL: nextURL)
                guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
                self.resolvedPages[nextURL] = page
                self.inFlightPageURLs.remove(nextURL)
                self.mergeResolvedPage(page, pageURL: nextURL)
            } catch {
                self.inFlightPageURLs.remove(nextURL)
                self.failedPageURLs.insert(nextURL)
            }
            // Check completion.
            if self.resolvedPages.count >= pageURLs.count {
                self.isResolutionComplete = true
            }
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
        cancelResolveTask()
        currentItem = nil
        imageSlots = []
        selectedSlotID = nil
        isResolving = false
        errorMessage = nil
        resolvedPages = [:]
        failedPageURLs = []
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
