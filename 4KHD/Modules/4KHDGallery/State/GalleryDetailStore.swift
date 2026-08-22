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
    var errorMessage: String?

    @ObservationIgnored private var currentItem: GalleryItem?
    @ObservationIgnored private var itemPageCursors: [GalleryItem.ID: Int] = [:]
    @ObservationIgnored private var requestedDetailPageIndexByURL: [URL: (itemID: GalleryItem.ID, cursor: Int)] = [:]
    @ObservationIgnored private var resolvedPageURLs: [GalleryItem.ID: [URL]] = [:]
    @ObservationIgnored private var requestedDetailPageURLs: [GalleryItem.ID: Set<URL>] = [:]
    @ObservationIgnored private var detailPageTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingSelectionIndex: Int?
    @ObservationIgnored private let prefetchDistance = 6
    @ObservationIgnored private let pageResolver: (URL) async throws -> ResolvedImagePage

    init(pageResolver: @escaping (URL) async throws -> ResolvedImagePage = DetailPageHTMLResolver.resolve) {
        self.pageResolver = pageResolver
    }

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
        errorMessage = nil
        cancelOutstandingDetailPageTasks()
        currentItem = item
        pendingSelectionIndex = nil
        prefetchPageURL = nil
        selectedImageIndex = 0
        loadedImageSlots = []
        itemPageCursors.removeAll()
        resolvedPageURLs.removeAll()
        requestedDetailPageURLs.removeAll()
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
            // 还没加载到这张：尝试拉下一页,记下用户目标 index,等 slot 到位后跳过去。
            if ensureNextDetailPageLoaded(reason: .selectedBeyondLoadedRange) {
                pendingSelectionIndex = index
            } else {
                // 没有更多页可拉:回退到已加载范围内的最后一张。
                selectedImageIndex = max(loadedImageSlots.count - 1, 0)
            }
            return
        }
        // 用户主动选中已加载位置:取消任何挂起的跳转意图,避免在途页
        // 到位时把选中强制拉回原目标。
        pendingSelectionIndex = nil
        selectedImageIndex = index
        ensureNextDetailPageLoadedIfApproachingEnd(from: index)
    }

    func stepImage(_ delta: Int) {
        let nextIndex = selectedImageIndex + delta
        if delta > 0, nextIndex >= loadedImageSlots.count {
            // 在尾部按"下一张"：拉下一页 + 挂 pendingSelectionIndex；
            // 不 force-restart 当前页（会反复打断已在解析的 task）。
            // 没有更多页可拉时停在末位,不悬挂 pending。
            if ensureNextDetailPageLoaded(reason: .steppedPastLoadedRange) {
                pendingSelectionIndex = loadedImageSlots.count
            } else {
                selectedImageIndex = max(loadedImageSlots.count - 1, 0)
            }
            return
        }
        selectImage(at: nextIndex)
    }

    func cancelOutstandingDetailPageLoads() {
        rollbackOutstandingDetailPageRequests()
        cancelOutstandingDetailPageTasks()
        prefetchPageURL = nil
    }

    // MARK: - 分页

    @discardableResult
    func ensureNextDetailPageLoaded(reason: DetailPageLoadReason) -> Bool {
        guard let item = currentItem else { return false }
        // 同一时间只解析一页:多页并发返回会按网络顺序乱序追加 slot,
        // 胶片条顺序与上一张/下一张导航全部错乱。上一页完成后
        // registerResolvedPage → chainLoadIfNeeded 会接力下一页。
        guard detailPageTasks.isEmpty else { return true }
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
    /// pending 跳转路径自行接力(pendingSelectionIndex 未满足时逐页拉取)。
    private func chainLoadIfNeeded() {
        guard pendingSelectionIndex == nil else { return }
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
        guard let pendingSelectionIndex else { return }
        guard loadedImageSlots.indices.contains(pendingSelectionIndex) else {
            // 目标还没加载到:继续拉下一页;没有更多页时停在已加载末尾并清空。
            if !ensureNextDetailPageLoaded(reason: .selectedBeyondLoadedRange),
               !loadedImageSlots.isEmpty {
                selectedImageIndex = loadedImageSlots.count - 1
                self.pendingSelectionIndex = nil
            }
            return
        }
        selectedImageIndex = pendingSelectionIndex
        self.pendingSelectionIndex = nil
    }

    private func resolveDetailPage(_ pageURL: URL) {
        let key = pageURL.absoluteString
        guard detailPageTasks[key] == nil else { return }
        errorMessage = nil
        detailPageTasks[key] = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.pageResolver(pageURL)
                guard !Task.isCancelled else { return }
                self.registerResolvedPage(page)
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "解析失败，请检查网络连接"
                self.markDetailPageResolutionFailed(pageURL)
            }
        }
    }

    private func markDetailPageResolutionFailed(_ pageURL: URL) {
        detailPageTasks[pageURL.absoluteString] = nil
        if prefetchPageURL == pageURL {
            prefetchPageURL = nil
        }
        if let request = requestedDetailPageIndexByURL.removeValue(forKey: pageURL) {
            itemPageCursors[request.itemID] = min(itemPageCursors[request.itemID, default: request.cursor], request.cursor)
            requestedDetailPageURLs[request.itemID]?.remove(pageURL)
        }
        // 失败页保持在当前 cursor，等待用户再次导航/接近尾部时重试；不能在本次
        // 详情生命周期内永久跳过，也不能自动跨过缺失页破坏图集顺序。
    }

    private func cancelOutstandingDetailPageTasks() {
        detailPageTasks.values.forEach { $0.cancel() }
        detailPageTasks.removeAll()
    }

    private func rollbackOutstandingDetailPageRequests() {
        let activePageURLs = requestedDetailPageIndexByURL.keys.filter {
            detailPageTasks[$0.absoluteString] != nil
        }
        for pageURL in activePageURLs {
            guard let request = requestedDetailPageIndexByURL.removeValue(forKey: pageURL) else { continue }
            itemPageCursors[request.itemID] = min(
                itemPageCursors[request.itemID, default: request.cursor],
                request.cursor
            )
            requestedDetailPageURLs[request.itemID]?.remove(pageURL)
        }
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
