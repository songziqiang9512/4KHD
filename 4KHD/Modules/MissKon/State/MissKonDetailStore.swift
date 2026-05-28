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

    private func cancelResolveTask() {
        resolveTask?.cancel()
        resolveTask = nil
        isResolving = false
    }

    /// Cancel in-flight page resolution without clearing current item, slots, or resolved pages.
    /// Use when detail pane closes — keeps the list selection's placeholder intact.
    func cancelResolution() {
        resolveTask?.cancel()
        resolveTask = nil
        isResolving = false
    }

    var resolvedPageCount: Int { resolvedPages.count }
    var resolvedImageCount: Int {
        resolvedPages.reduce(0) { $0 + $1.value.imageURLs.count }
    }

    func imageURL(for slot: MissKonImageSlot) -> URL? {
        if let knownURL = slot.knownURL { return knownURL }
        return resolvedPages[slot.pageURL]?.imageURLs.element(at: slot.pageImageIndex)
    }

    /// Set up placeholder state without starting network resolution.
    /// Called on list selection so detail pane can show cover immediately.
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

        imageSlots = [MissKonImageSlot(
            id: "\(item.id)-init",
            displayIndex: 0,
            pageURL: pageURLs[0],
            pageImageIndex: 0,
            knownURL: item.coverURL
        )]
        selectedSlotID = imageSlots[0].id
    }

    /// Start resolving detail pages. Called when detail pane or immersive opens.
    func resolve(item: MissKonItem, force: Bool = false) {
        guard force || item.id == currentItem?.id else { return }
        if force {
            cancelResolveTask()
            resolvedPages = [:]
            failedPageURLs = []
            errorMessage = nil
            isResolutionComplete = false
        }
        let pageURLs = item.pageURLs
        guard !pageURLs.isEmpty else { return }
        let itemID = item.id

        resolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.currentItem?.id == itemID {
                    self.isResolving = false
                    self.resolveTask = nil
                }
            }
            self.isResolving = true

            // Resume: filter out already-resolved or previously-failed pages.
            var pendingURLs = pageURLs.filter {
                !self.resolvedPages.keys.contains($0) && !self.failedPageURLs.contains($0)
            }
            if pendingURLs.isEmpty, !self.resolvedPages.isEmpty {
                // All pages previously resolved; skip to publish.
                self.publishSlots()
                self.isResolutionComplete = true
                return
            }
            var seenURLs = Set(pageURLs)
            var resolvedAny = !self.resolvedPages.isEmpty

            // Resolve first pending page eagerly and publish immediately
            if let firstURL = pendingURLs.first {
                pendingURLs.removeFirst()
                do {
                    let page = try await MissKonDetailResolver.resolve(pageURL: firstURL)
                    guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
                    self.resolvedPages[firstURL] = page
                    for newURL in page.pageURLs where seenURLs.insert(newURL).inserted {
                        if !self.resolvedPages.keys.contains(newURL), !self.failedPageURLs.contains(newURL) {
                            pendingURLs.append(newURL)
                        }
                    }
                    resolvedAny = true
                    self.publishSlots()
                } catch {
                    self.failedPageURLs.insert(firstURL)
                }
            }

            // Resolve remaining pages in small parallel batches (cap at 50 pages, 2 per batch).
            while !pendingURLs.isEmpty, !Task.isCancelled, self.resolvedPages.count < 50 {
                let maxBatch = min(2, 50 - self.resolvedPages.count)
                let batch = Array(pendingURLs.prefix(maxBatch))
                pendingURLs.removeFirst(min(pendingURLs.count, batch.count))

                let batchResults: [(URL, Result<MissKonResolvedImagePage, Error>)] = await withTaskGroup(
                    of: (URL, Result<MissKonResolvedImagePage, Error>).self
                ) { group in
                    for url in batch {
                        group.addTask {
                            do {
                                let page = try await MissKonDetailResolver.resolve(pageURL: url)
                                return (url, .success(page))
                            } catch {
                                return (url, .failure(error))
                            }
                        }
                    }
                    var results: [(URL, Result<MissKonResolvedImagePage, Error>)] = []
                    for await result in group { results.append(result) }
                    return results
                }

                guard !Task.isCancelled, self.currentItem?.id == itemID else { return }

                var newURLs: [URL] = []
                for (url, result) in batchResults {
                    switch result {
                    case .success(let page):
                        self.resolvedPages[url] = page
                        for newURL in page.pageURLs where seenURLs.insert(newURL).inserted {
                            if !self.resolvedPages.keys.contains(newURL), !self.failedPageURLs.contains(newURL) {
                                newURLs.append(newURL)
                            }
                        }
                        resolvedAny = true
                    case .failure:
                        self.failedPageURLs.insert(url)
                    }
                }
                pendingURLs.append(contentsOf: newURLs)
                self.publishSlots()
            }

            guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
            if !resolvedAny {
                self.errorMessage = "无法解析任何图片"
            }
            self.isResolutionComplete = true
        }
    }

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

    private func publishSlots() {
        let sortedPages = resolvedPages.keys.sorted { a, b in
            let aNum = a.trailingPageNumber ?? 1
            let bNum = b.trailingPageNumber ?? 1
            return aNum < bNum
        }

        var allSlots: [MissKonImageSlot] = []
        var globalDisplayIndex = 0
        for pageURL in sortedPages {
            guard let page = resolvedPages[pageURL] else { continue }
            for (imageIndex, imageURL) in page.imageURLs.enumerated() {
                let slotID = "\(pageURL.absoluteString)-\(imageIndex)"
                allSlots.append(MissKonImageSlot(
                    id: slotID,
                    displayIndex: globalDisplayIndex,
                    pageURL: pageURL,
                    pageImageIndex: imageIndex,
                    knownURL: imageURL
                ))
                globalDisplayIndex += 1
            }
        }

        if !allSlots.isEmpty {
            imageSlots = allSlots
            errorMessage = nil
            if selectedSlotID == nil || !allSlots.contains(where: { $0.id == selectedSlotID }) {
                selectedSlotID = allSlots.first?.id
            }
        }
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
