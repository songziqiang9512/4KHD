import Foundation

/// 当前选中图集的 slot 模型 + 分页解析 + 链式接力。
/// 不关心列表 / 搜索 / 收藏。
/// 调用方（`FourKHDGalleryStore`）在 Feed 的 `selectedItem` 变化时调用 `prepare(for:)`
/// 让 detail 重建状态。
@MainActor
@Observable
final class GalleryDetailStore {
    var selectedImageIndex = 0
    private(set) var loadedImageSlots: [ImageSlot] = []
    private(set) var prefetchPageURL: URL?
    var isFullscreenViewerPresented = false

    @ObservationIgnored private var currentItem: GalleryItem?
    @ObservationIgnored private var itemPageCursors: [GalleryItem.ID: Int] = [:]
    @ObservationIgnored private var requestedDetailPageIndexByURL: [URL: (itemID: GalleryItem.ID, cursor: Int)] = [:]
    @ObservationIgnored private var resolvedPageURLs: [GalleryItem.ID: [URL]] = [:]
    @ObservationIgnored private var requestedDetailPageURLs: [GalleryItem.ID: Set<URL>] = [:]
    @ObservationIgnored private var detailPageTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingSelectionIndex: Int?
    @ObservationIgnored private let prefetchDistance = 6

    // MARK: - 派生

    var selectedSlot: ImageSlot? {
        guard loadedImageSlots.indices.contains(selectedImageIndex) else { return loadedImageSlots.first }
        return loadedImageSlots[selectedImageIndex]
    }

    var upcomingKnownImageURLs: [URL] {
        let startIndex = max(selectedImageIndex + 1, 0)
        guard startIndex < loadedImageSlots.count else { return [] }
        return loadedImageSlots[startIndex...]
            .prefix(8)
            .compactMap(\.knownURL)
    }

    // MARK: - 生命周期

    /// 切换 / 重选当前图集时调用：重建 slot、cursor、清掉 in-flight 任务。
    func prepare(for item: GalleryItem?) {
        cancelOutstandingDetailPageTasks()
        currentItem = item
        pendingSelectionIndex = nil
        prefetchPageURL = nil
        selectedImageIndex = 0
        loadedImageSlots = []
        requestedDetailPageIndexByURL.removeAll()
        guard let item else { return }
        itemPageCursors[item.id] = min(pageURLs(for: item).count, 1)
        requestedDetailPageURLs[item.id] = Set(pageURLs(for: item).prefix(1))
        appendSlots(for: item, pageOffset: 0, knownURLs: item.sampleImageURLs)
    }

    // MARK: - 选择

    func selectImage(at index: Int) {
        guard index >= 0 else { return }
        if index >= loadedImageSlots.count {
            // 还没加载到这张：尝试拉下一页，并挂上 pendingSelectionIndex，等 slot 到位后跳过去。
            ensureNextDetailPageLoaded(reason: .selectedBeyondLoadedRange)
            pendingSelectionIndex = loadedImageSlots.count
            return
        }
        selectedImageIndex = index
        ensureNextDetailPageLoadedIfApproachingEnd(from: index)
    }

    func stepImage(_ delta: Int) {
        let nextIndex = selectedImageIndex + delta
        if delta > 0, nextIndex >= loadedImageSlots.count {
            // 在尾部按"下一张"：拉下一页 + 挂 pendingSelectionIndex；
            // 不 force-restart 当前页（会反复打断已在解析的 task）。
            ensureNextDetailPageLoaded(reason: .steppedPastLoadedRange)
            pendingSelectionIndex = loadedImageSlots.count
            return
        }
        selectImage(at: nextIndex)
    }

    func cancelOutstandingDetailPageLoads() {
        cancelOutstandingDetailPageTasks()
        prefetchPageURL = nil
    }

    // MARK: - 分页

    @discardableResult
    func ensureNextDetailPageLoaded(reason: DetailPageLoadReason) -> Bool {
        guard let item = currentItem else { return false }
        let cursor = itemPageCursors[item.id, default: 1]
        let pageURLs = pageURLs(for: item)
        guard cursor < pageURLs.count else { return false }
        let pageURL = pageURLs[cursor]
        guard requestedDetailPageURLs[item.id, default: []].insert(pageURL).inserted else {
            // 已发过请求还没回，视为在路上。
            return true
        }
        requestedDetailPageIndexByURL[pageURL] = (item.id, cursor)
        itemPageCursors[item.id] = cursor + 1
        prefetchPageURL = pageURL
        resolveDetailPage(pageURL)
        return true
    }

    private func ensureNextDetailPageLoadedIfApproachingEnd(from index: Int) {
        guard isApproachingLoadedEnd(from: index) else { return }
        ensureNextDetailPageLoaded(reason: .approachingLoadedEnd)
    }

    func registerResolvedPage(_ page: ResolvedImagePage) {
        guard let item = currentItem else { return }
        let isExpectedPage = pageURLs(for: item).contains(page.pageURL)
            || loadedImageSlots.contains(where: { $0.pageURL == page.pageURL })
            || requestedDetailPageURLs[item.id, default: []].contains(page.pageURL)
        guard isExpectedPage else { return }
        mergeResolvedPageURLs(page.pageURLs, for: item)
        if prefetchPageURL == page.pageURL {
            prefetchPageURL = nil
        }
        requestedDetailPageIndexByURL[page.pageURL] = nil
        detailPageTasks[page.pageURL.absoluteString] = nil

        if let firstIndex = loadedImageSlots.firstIndex(where: { $0.pageURL == page.pageURL }),
           let lastIndex = loadedImageSlots.lastIndex(where: { $0.pageURL == page.pageURL }) {
            let startDisplayIndex = loadedImageSlots[firstIndex].displayIndex
            let resolvedSlots = page.imageURLs.enumerated().map { offset, imageURL in
                ImageSlot(
                    id: "\(item.id)-\(startDisplayIndex + offset)",
                    displayIndex: startDisplayIndex + offset,
                    pageURL: page.pageURL,
                    pageImageIndex: offset,
                    knownURL: imageURL
                )
            }
            loadedImageSlots.replaceSubrange(firstIndex...lastIndex, with: resolvedSlots)
            selectedImageIndex = min(selectedImageIndex, max(loadedImageSlots.count - 1, 0))
            applyPendingSelectionIfPossible()
            chainLoadIfNeeded()
            return
        }
        appendResolvedSlots(for: item, page: page)
        applyPendingSelectionIfPossible()
        chainLoadIfNeeded()
    }

    /// 只在用户已经接近当前已加载尾部时接力，避免大图集在后台一路解析太远。
    private func chainLoadIfNeeded() {
        guard isApproachingLoadedEnd(from: selectedImageIndex) else { return }
        ensureNextDetailPageLoaded(reason: .approachingLoadedEnd)
    }

    private func isApproachingLoadedEnd(from index: Int) -> Bool {
        loadedImageSlots.count - index <= prefetchDistance
    }

    // MARK: - 内部

    private func appendSlots(for item: GalleryItem, pageOffset: Int, knownURLs: [URL]) {
        let pageURLs = pageURLs(for: item)
        guard pageURLs.indices.contains(pageOffset) else { return }
        let currentCount = loadedImageSlots.count
        let pageURL = pageURLs[pageOffset]
        let count = max(knownURLs.count, 1)
        let newSlots = (0..<count).map { offset in
            ImageSlot(
                id: "\(item.id)-\(currentCount + offset + 1)",
                displayIndex: currentCount + offset + 1,
                pageURL: pageURL,
                pageImageIndex: offset,
                knownURL: knownURLs.indices.contains(offset) ? knownURLs[offset] : nil
            )
        }
        loadedImageSlots.append(contentsOf: newSlots)
    }

    private func appendResolvedSlots(for item: GalleryItem, page: ResolvedImagePage) {
        let currentCount = loadedImageSlots.count
        let newSlots = page.imageURLs.enumerated().map { offset, imageURL in
            ImageSlot(
                id: "\(item.id)-\(currentCount + offset + 1)",
                displayIndex: currentCount + offset + 1,
                pageURL: page.pageURL,
                pageImageIndex: offset,
                knownURL: imageURL
            )
        }
        loadedImageSlots.append(contentsOf: newSlots)
    }

    private func applyPendingSelectionIfPossible() {
        guard let pendingSelectionIndex,
              loadedImageSlots.indices.contains(pendingSelectionIndex) else { return }
        selectedImageIndex = pendingSelectionIndex
        self.pendingSelectionIndex = nil
    }

    private func resolveDetailPage(_ pageURL: URL) {
        let key = pageURL.absoluteString
        guard detailPageTasks[key] == nil else { return }
        detailPageTasks[key] = Task { [weak self] in
            do {
                let page = try await DetailPageHTMLResolver.resolve(pageURL: pageURL)
                guard !Task.isCancelled else { return }
                self?.registerResolvedPage(page)
            } catch {
                guard !Task.isCancelled else { return }
                self?.markDetailPageResolutionFailed(pageURL)
            }
        }
    }

    private func markDetailPageResolutionFailed(_ pageURL: URL) {
        detailPageTasks[pageURL.absoluteString] = nil
        if prefetchPageURL == pageURL {
            prefetchPageURL = nil
        }
        // 失败时清掉 requested set 里这条，让链路在合适时机能再次考虑它；
        // cursor 回滚到失败页，避免后续直接跳过这一页。
        if let request = requestedDetailPageIndexByURL.removeValue(forKey: pageURL) {
            itemPageCursors[request.itemID] = min(itemPageCursors[request.itemID, default: request.cursor], request.cursor)
        }
        for itemID in requestedDetailPageURLs.keys {
            requestedDetailPageURLs[itemID]?.remove(pageURL)
        }
        chainLoadIfNeeded()
    }

    private func cancelOutstandingDetailPageTasks() {
        detailPageTasks.values.forEach { $0.cancel() }
        detailPageTasks.removeAll()
    }

    private func pageURLs(for item: GalleryItem) -> [URL] {
        resolvedPageURLs[item.id] ?? item.pageURLs
    }

    private func mergeResolvedPageURLs(_ pageURLs: [URL], for item: GalleryItem) {
        guard !pageURLs.isEmpty else { return }
        var merged = self.pageURLs(for: item)
        for pageURL in pageURLs where !merged.contains(pageURL) {
            merged.append(pageURL)
        }
        resolvedPageURLs[item.id] = merged.sorted { lhs, rhs in
            pageNumber(lhs, detailURL: item.detailURL) < pageNumber(rhs, detailURL: item.detailURL)
        }
    }

    private func pageNumber(_ url: URL, detailURL: URL) -> Int {
        let detailPath = detailURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path != detailPath else { return 1 }
        return Int(path.split(separator: "/").last ?? "") ?? 1
    }
}

enum DetailPageLoadReason {
    case approachingLoadedEnd
    case filmstripReachedEnd
    case selectedBeyondLoadedRange
    case steppedPastLoadedRange
}
