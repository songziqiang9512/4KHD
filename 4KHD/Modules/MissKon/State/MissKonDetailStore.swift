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

    func resolve(item: MissKonItem, force: Bool = false) {
        guard force || item.id != currentItem?.id else { return }
        cancelResolveTask()
        resolvedPages = [:]
        failedPageURLs = []
        isResolving = false
        errorMessage = nil
        imageSlots = []
        selectedSlotID = nil

        currentItem = item
        let pageURLs = item.pageURLs
        let itemID = item.id

        guard !pageURLs.isEmpty else { return }

        resolveTask = Task { [weak self] in
            guard let self else { return }
            self.isResolving = true

            var pendingURLs = pageURLs
            var seenURLs = Set(pageURLs)
            var resolvedAny = false

            // Resolve first page eagerly and publish immediately
            if let firstURL = pendingURLs.first {
                pendingURLs.removeFirst()
                do {
                    let page = try await MissKonDetailResolver.resolve(pageURL: firstURL)
                    guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
                    self.resolvedPages[firstURL] = page
                    for newURL in page.pageURLs where seenURLs.insert(newURL).inserted {
                        pendingURLs.append(newURL)
                    }
                    resolvedAny = true
                    self.publishSlots()
                } catch {
                    self.failedPageURLs.insert(firstURL)
                }
            }

            // Resolve remaining pages
            while !pendingURLs.isEmpty, !Task.isCancelled {
                let pageURL = pendingURLs.removeFirst()
                do {
                    let page = try await MissKonDetailResolver.resolve(pageURL: pageURL)
                    guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
                    self.resolvedPages[pageURL] = page
                    for newURL in page.pageURLs where seenURLs.insert(newURL).inserted {
                        pendingURLs.append(newURL)
                    }
                    resolvedAny = true
                    self.publishSlots()
                } catch {
                    self.failedPageURLs.insert(pageURL)
                }
            }

            guard !Task.isCancelled, self.currentItem?.id == itemID else { return }
            if !resolvedAny {
                self.errorMessage = "无法解析任何图片"
            }
            self.isResolving = false
        }
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
