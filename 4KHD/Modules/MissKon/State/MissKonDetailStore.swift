import Foundation
import Observation

@MainActor
@Observable
final class MissKonDetailStore {
    var currentItem: MissKonItem?
    var imageSlots: [MissKonImageSlot] = []
    var selectedSlotID: MissKonImageSlot.ID?
    var isResolving = false
    var errorMessage: String?

    private var resolvedPages: [URL: MissKonResolvedImagePage] = [:]
    private var failedPageURLs = Set<URL>()
    private var resolveTask: Task<Void, Never>?

    private func cancelResolveTask() {
        resolveTask?.cancel()
    }

    var resolvedImageCount: Int {
        resolvedPages.reduce(0) { $0 + $1.value.imageURLs.count }
    }

    func imageURL(for slot: MissKonImageSlot) -> URL? {
        if let knownURL = slot.knownURL { return knownURL }
        return resolvedPages[slot.pageURL]?.imageURLs.element(at: slot.pageImageIndex)
    }

    func resolve(item: MissKonItem) {
        guard item.id != currentItem?.id else { return }
        cancelResolveTask()
        resolvedPages = [:]
        failedPageURLs = []
        isResolving = false
        errorMessage = nil

        currentItem = item
        let pageURLs = item.pageURLs
        let itemID = item.id

        guard !pageURLs.isEmpty else { return }

        resolveTask = Task { [weak self] in
            guard let self else { return }
            self.isResolving = true

            var allSlots: [MissKonImageSlot] = []
            var globalDisplayIndex = 0

            var resolvedAny = false

            for pageURL in pageURLs {
                guard !Task.isCancelled else { return }
                do {
                    let page = try await MissKonDetailResolver.resolve(pageURL: pageURL)
                    guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
                    self.resolvedPages[pageURL] = page

                    // Use the union of known page URLs from all resolved pages
                    let mergedPages: [URL]
                    if page.pageURLs.count > self.resolvedPageURLs.count {
                        mergedPages = page.pageURLs
                    } else {
                        mergedPages = self.resolvedPageURLs
                    }

                    // Ensure subsequent pages exist
                    for pu in mergedPages {
                        if self.resolvedPages[pu] == nil && pu != pageURL {
                            // Will be resolved in the loop
                        }
                    }

                    resolvedAny = true
                } catch {
                    self.failedPageURLs.insert(pageURL)
                }
            }

            // Build slots from all resolved pages
            allSlots = []
            globalDisplayIndex = 0
            let sortedPages = self.resolvedPages.keys.sorted { a, b in
                let aNum = a.trailingPageNumber ?? 1
                let bNum = b.trailingPageNumber ?? 1
                return aNum < bNum
            }

            for pageURL in sortedPages {
                guard let page = self.resolvedPages[pageURL] else { continue }
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

            guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
            self.imageSlots = allSlots
            if resolvedAny {
                self.errorMessage = nil
            } else {
                self.errorMessage = "无法解析任何图片"
            }
            self.isResolving = false
        }
    }

    private var resolvedPageURLs: [URL] {
        Array(resolvedPages.keys)
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
