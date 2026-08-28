import Foundation
import Observation

/// 收藏模块的详情状态:统一 slot 模型,按来源适配器解析,
/// 行为与 MissKon 详情一致:占位 slot + 渐进分页解析 + 失败页可恢复重试。
/// Wallhaven 收藏记录先显示封面,再经来源适配器解析并升级为原图。
@MainActor
@Observable
final class FavoritesDetailStore {
    // A corrupted/stale favorite can report thousands of images. Building the
    // entire filmstrip synchronously would block AppKit's MainActor. Start with
    // a bounded progressive window; pages without placeholders are inserted
    // normally by replaceSlots when they resolve, so no final images are lost.
    private static let maximumInitialSlotCount = 1_000
    private(set) var currentRecord: FavoriteRecord?
    private(set) var currentSource: FavoriteSource?
    private(set) var imageSlots: [FavoritesImageSlot] = []
    var selectedSlotID: FavoritesImageSlot.ID?
    private(set) var isResolving = false
    private(set) var resolvedPageCount = 0
    private(set) var resolvedImageCount = 0
    private(set) var errorMessage: String?
    private(set) var recommendations: [OnlineGalleryRecommendation] = []
    private(set) var detailMetadata: FavoriteDetailMetadata?
    private(set) var videoURL: URL?
    private(set) var externalAction: FavoriteDetailExternalAction?
    private(set) var contentMode: WorkspaceDetailContentMode = .image

    private struct ResolvedPage {
        let imageURLs: [URL]
        let pageURLs: [URL]
        let recommendations: [OnlineGalleryRecommendation]
        let metadata: FavoriteDetailMetadata?
        let videoURL: URL?
        let externalAction: FavoriteDetailExternalAction?
    }

    private enum PendingNavigationTarget {
        case slot(pageURL: URL, pageImageIndex: Int)
        case afterLastImage
    }

    private var resolvedPages: [URL: ResolvedPage] = [:]
    private var failedPageURLs = Set<URL>()
    /// All page URLs discovered so far (initial + discovered via page.pageURLs).
    private var knownPageURLs: [URL] = []
    /// Per-page in-flight tasks.
    private var pageTasks: [URL: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingNavigationTarget: PendingNavigationTarget?
    @ObservationIgnored private var pageImageCapacity = 1
    @ObservationIgnored private let sourceAdapters: FavoriteSourceAdapterRegistry

    init(sourceAdapters: FavoriteSourceAdapterRegistry = .shared) {
        self.sourceAdapters = sourceAdapters
    }

    var selectedSlot: FavoritesImageSlot? {
        guard let selectedSlotID else { return nil }
        return imageSlots.first { $0.id == selectedSlotID }
    }

    var canStepBackward: Bool {
        contentMode == .recommendations || selectedIndex > 0
    }

    var canStepForward: Bool {
        guard contentMode == .image else { return false }
        if selectedIndex < imageSlots.count - 1 { return true }
        if isResolutionComplete { return !recommendations.isEmpty }
        return hasPendingResolution
    }

    var isResolutionComplete: Bool {
        !knownPageURLs.isEmpty
            && pageTasks.isEmpty
            && knownPageURLs.allSatisfy { resolvedPages[$0] != nil }
    }

    var hasResolvedSelectedImage: Bool { selectedSlotRepresentsResolvedImage }

    var canPlayVideo: Bool {
        currentVideoContext != nil
    }

    var canSaveVideo: Bool {
        currentVideoContext != nil
    }

    var navigationMode: FavoriteDetailNavigationMode {
        guard let record = currentRecord else { return .images }
        return sourceAdapters.adapter(for: record)?.navigationMode ?? .images
    }

    func imageURL(for slot: FavoritesImageSlot) -> URL? {
        if let knownURL = slot.knownURL { return knownURL }
        guard let pageURL = slot.pageURL else { return nil }
        return resolvedPages[pageURL]?.imageURLs.element(at: slot.pageImageIndex)
    }

    // MARK: - Prepare

    func prepare(record: FavoriteRecord?) {
        cancelAllPageTasks()
        resolvedPages = [:]
        failedPageURLs = []
        knownPageURLs = []
        resolvedPageCount = 0
        resolvedImageCount = 0
        isResolving = false
        errorMessage = nil
        recommendations = []
        detailMetadata = nil
        videoURL = nil
        externalAction = nil
        contentMode = .image
        pendingNavigationTarget = nil
        pageImageCapacity = 1
        imageSlots = []
        selectedSlotID = nil
        currentRecord = record
        currentSource = record.flatMap(FavoriteSource.source(for:))

        guard let record, let source = currentSource else { return }

        guard let adapter = sourceAdapters.adapter(for: source),
              let content = adapter.detailContent(record) else { return }
        detailMetadata = adapter.detailMetadata(record)
        let pageURLs: [URL]
        let estimatedImageCount: Int
        switch content {
        case .paged(let urls, let count, let capacity):
            pageURLs = urls
            estimatedImageCount = count
            pageImageCapacity = max(capacity, 1)
        case .singleImage(let imageURL):
            imageSlots = [FavoritesImageSlot(
                id: "\(record.id)-cover",
                displayIndex: 0,
                pageURL: nil,
                pageImageIndex: 0,
                knownURL: imageURL
            )]
            selectedSlotID = imageSlots.first?.id
            return
        }

        var seenPageURLs = Set<URL>()
        knownPageURLs = pageURLs.filter { seenPageURLs.insert($0).inserted }
        guard !knownPageURLs.isEmpty else { return }

        // 首页缓存命中直接建立已解析页。
        if let cached = DetailPageImageCache.shared.page(for: knownPageURLs[0]),
           let cachedRecommendations = cached.recommendations {
            resolvedPages[cached.pageURL] = ResolvedPage(
                imageURLs: cached.imageURLs,
                pageURLs: cached.pageURLs,
                recommendations: cachedRecommendations,
                metadata: nil,
                videoURL: nil,
                externalAction: adapter.cachedExternalAction(cached.pageURL)
            )
            reconcileKnownPageURLs(with: cached.pageURLs, requestedPageURL: cached.pageURL)
            // 缓存页不会走 merge,计数在此补上(merge 改为增量累加后)。
            resolvedPageCount = 1
            resolvedImageCount = cached.imageURLs.count
            mergeRecommendations(cachedRecommendations)
        }

        // 生成占位 slot:已知图片的 slot 直接带 URL,其余等待解析填充。
        let count = min(max(estimatedImageCount, 1), Self.maximumInitialSlotCount)
        var slots: [FavoritesImageSlot] = []
        for globalIndex in 0 ..< count {
            let pageIndex = min(globalIndex / pageImageCapacity, knownPageURLs.count - 1)
            let imageInPage = globalIndex % pageImageCapacity
            let pageURL = knownPageURLs[pageIndex]
            let cachedImageURL = resolvedPages[pageURL]?.imageURLs.element(at: imageInPage)
            slots.append(FavoritesImageSlot(
                id: "\(record.id)-p\(pageIndex)-i\(imageInPage)",
                displayIndex: globalIndex,
                pageURL: pageURL,
                pageImageIndex: imageInPage,
                knownURL: cachedImageURL ?? (globalIndex == 0 ? source.validatedCoverURL(for: record) : nil)
            ))
        }
        imageSlots = slots
        if let firstPageURL = knownPageURLs.first,
           let cachedPage = resolvedPages[firstPageURL] {
            replaceSlots(
                for: firstPageURL,
                with: resolvedSlots(for: cachedPage, pageURL: firstPageURL, record: record)
            )
        }
        selectedSlotID = imageSlots.first?.id
        refreshExternalAction()
    }

    // MARK: - 渐进解析

    /// 开始解析首页(未缓存时),随后按连续页序预取 2 页。
    /// 重复调用安全。
    func resolve() {
        guard currentSource != nil,
              currentRecord != nil,
              pageTasks.isEmpty,
              !knownPageURLs.isEmpty else { return }
        if resolvedPages.keys.contains(knownPageURLs[0]) {
            // 首页已解析(缓存命中):继续加载下一页;没有可加载页时结束解析状态。
            schedulePrefetch(count: 2, after: knownPageURLs[0])
            if pageTasks.isEmpty {
                isResolving = false
            }
            return
        }
        loadPage(knownPageURLs[0], prefetchNext: 2)
    }

    /// 用户导航到某 slot:其页未解析时按需加载。
    func ensurePageLoadedForSlot(at displayIndex: Int) {
        guard imageSlots.indices.contains(displayIndex) else { return }
        let slot = imageSlots[displayIndex]
        guard slot.knownURL == nil,
              let pageURL = slot.pageURL,
              !resolvedPages.keys.contains(pageURL) else { return }
        pendingNavigationTarget = .slot(
            pageURL: pageURL,
            pageImageIndex: slot.pageImageIndex
        )
        loadNextUnresolvedPage()
    }

    /// 接近已解析尾部时加载下一页(与 MissKon 详情相同的阈值策略)。
    func ensureNextDetailPageLoadedIfApproachingEnd(from index: Int) {
        let maxResolved = imageSlots.lastIndex(where: { $0.knownURL != nil }) ?? 0
        guard index >= max(maxResolved - 4, 0) else { return }
        loadNextUnresolvedPage()
    }

    func retry() {
        guard currentRecord != nil else { return }
        guard !failedPageURLs.isEmpty else {
            resolve()
            return
        }
        failedPageURLs.removeAll()
        refreshFailureMessage()
        loadNextUnresolvedPage()
    }

    func cancelResolution() {
        cancelAllPageTasks()
        pendingNavigationTarget = nil
    }

    func selectSlot(at displayIndex: Int) {
        guard imageSlots.indices.contains(displayIndex) else { return }
        let slot = imageSlots[displayIndex]
        contentMode = .image
        guard isResolvedNavigableImage(at: displayIndex) else {
            guard let pageURL = slot.pageURL else { return }
            pendingNavigationTarget = .slot(
                pageURL: pageURL,
                pageImageIndex: slot.pageImageIndex
            )
            resumePendingResolutionFromUserAction()
            return
        }
        pendingNavigationTarget = nil
        selectedSlotID = slot.id
        ensureNextDetailPageLoadedIfApproachingEnd(from: displayIndex)
    }

    func stepSelection(_ delta: Int) {
        if contentMode == .recommendations {
            guard delta < 0 else { return }
            contentMode = .image
            pendingNavigationTarget = nil
            selectedSlotID = imageSlots.last?.id
            return
        }

        guard !imageSlots.isEmpty else { return }
        let next = selectedIndex + delta
        if delta > 0, next >= imageSlots.count {
            // 最后一个槽仍是占位（包括仅有封面、原页尚未解析）时，
            // “下一张”只负责把这张原图解析出来。
            // 不能记录越界跳转意图，否则页面返回后会直接进入推荐，用户看不到刚加载的末图。
            if !selectedSlotRepresentsResolvedImage {
                if let selectedSlot, let pageURL = selectedSlot.pageURL {
                    pendingNavigationTarget = .slot(
                        pageURL: pageURL,
                        pageImageIndex: selectedSlot.pageImageIndex
                    )
                }
                resumePendingResolutionFromUserAction()
                return
            }
            if isResolutionComplete, !recommendations.isEmpty {
                contentMode = .recommendations
            } else if !isResolutionComplete {
                pendingNavigationTarget = .afterLastImage
                resumePendingResolutionFromUserAction()
            }
            return
        }
        let boundedNext = min(max(next, 0), imageSlots.count - 1)
        if delta > 0, !isResolvedNavigableImage(at: boundedNext) {
            let targetSlot = imageSlots[boundedNext]
            if let pageURL = targetSlot.pageURL {
                pendingNavigationTarget = .slot(
                    pageURL: pageURL,
                    pageImageIndex: targetSlot.pageImageIndex
                )
            }
            resumePendingResolutionFromUserAction()
            return
        }
        selectSlot(at: boundedNext)
    }

    // MARK: - 页加载

    private func loadPage(_ pageURL: URL, prefetchNext: Int = 0) {
        guard !pageTasks.keys.contains(pageURL),
              !resolvedPages.keys.contains(pageURL),
              !failedPageURLs.contains(pageURL) else { return }

        let recordSnapshot = currentRecord
        pageTasks[pageURL] = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.resolvePage(pageURL)
                guard !Task.isCancelled,
                      self.currentRecord == recordSnapshot,
                      self.pageTasks[pageURL] != nil else { return }
                self.reconcileKnownPageURLs(with: page.pageURLs, requestedPageURL: pageURL)
                self.resolvedPages[pageURL] = page
                self.failedPageURLs.remove(pageURL)
                self.pageTasks[pageURL] = nil
                self.mergeRecommendations(page.recommendations)
                self.mergeResolvedPage(page, pageURL: pageURL)
                if prefetchNext > 0 {
                    self.schedulePrefetch(count: prefetchNext, after: pageURL)
                }
                self.continuePendingNavigationIfNeeded()
                if self.pageTasks.isEmpty {
                    self.isResolving = false
                }
            } catch {
                guard !Task.isCancelled,
                      self.currentRecord == recordSnapshot,
                      self.pageTasks[pageURL] != nil else { return }
                self.pageTasks[pageURL] = nil
                self.failedPageURLs.insert(pageURL)
                self.refreshFailureMessage()
                self.continuePendingNavigationIfNeeded()
                self.isResolving = !self.pageTasks.isEmpty
            }
        }
        if pageTasks.count == 1 { isResolving = true }
    }

    /// 解析成功后按连续前缀预取接下来的若干页。一次只启动当前最早
    /// 的缺口；它完成后再链到下一页，避免前页仍在途时提前请求后页。
    private func schedulePrefetch(count: Int, after pageURL: URL) {
        guard count > 0, knownPageURLs.contains(pageURL) else { return }
        let prefixCount = contiguousResolvedPageCount
        guard knownPageURLs.indices.contains(prefixCount) else { return }
        let candidate = knownPageURLs[prefixCount]
        guard !failedPageURLs.contains(candidate),
              !resolvedPages.keys.contains(candidate),
              !pageTasks.keys.contains(candidate) else { return }
        loadPage(candidate, prefetchNext: count - 1)
    }

    private func resolvePage(_ pageURL: URL) async throws -> ResolvedPage {
        guard let record = currentRecord,
              let adapter = sourceAdapters.adapter(for: record) else {
            throw URLError(.unsupportedURL)
        }
        let page = try await adapter.resolvePage(pageURL)
        return ResolvedPage(
            imageURLs: page.imageURLs,
            pageURLs: page.pageURLs,
            recommendations: page.recommendations,
            metadata: page.metadata,
            videoURL: page.videoURL,
            externalAction: page.externalAction
        )
    }

    private func loadNextUnresolvedPage() {
        let prefixCount = contiguousResolvedPageCount
        guard prefixCount < knownPageURLs.count else {
            if pageTasks.isEmpty {
                isResolving = false
            }
            return
        }

        // Only the first gap after the contiguous prefix is eligible. If it is
        // already in flight, wait for it instead of starting the following page.
        let candidate = knownPageURLs[prefixCount]
        if failedPageURLs.contains(candidate) { return }
        guard !resolvedPages.keys.contains(candidate),
              !pageTasks.keys.contains(candidate) else { return }
        loadPage(candidate)
    }

    private func reconcileKnownPageURLs(with resolvedPageURLs: [URL], requestedPageURL: URL) {
        guard !resolvedPageURLs.isEmpty else { return }
        var seen = Set<URL>()
        let normalized = resolvedPageURLs
            .filter { seen.insert($0).inserted }
            .sorted { ($0.detailPageNumber ?? 1) < ($1.detailPageNumber ?? 1) }
        guard normalized.contains(requestedPageURL) else { return }

        let resolvedSet = Set(normalized)
        let removedPageURLs = knownPageURLs.filter { !resolvedSet.contains($0) }
        guard !removedPageURLs.isEmpty || normalized != knownPageURLs else { return }

        for pageURL in removedPageURLs {
            pageTasks[pageURL]?.cancel()
            pageTasks[pageURL] = nil
            if let removed = resolvedPages.removeValue(forKey: pageURL) {
                resolvedImageCount -= removed.imageURLs.count
            }
            failedPageURLs.remove(pageURL)
        }
        knownPageURLs = normalized
        pruneSlots(excluding: removedPageURLs)
        resolvedPageCount = resolvedPages.count
        refreshFailureMessage()
        refreshVideoURL()
        refreshExternalAction()
    }

    /// 用解析结果替换该页的占位 slot。
    private func mergeResolvedPage(_ page: ResolvedPage, pageURL: URL) {
        guard let record = currentRecord else { return }
        replaceSlots(
            for: pageURL,
            with: resolvedSlots(for: page, pageURL: pageURL, record: record)
        )
        if let metadata = page.metadata {
            detailMetadata = metadata
        }
        refreshVideoURL()
        refreshExternalAction()
        refreshFailureMessage()
        if resolvedPages.count > 0 {
            resolvedPageCount = resolvedPages.count
            // merge 的页此前未解析(loadPage 有 resolvedPages 去重 guard),增量累加即可。
            resolvedImageCount += page.imageURLs.count
        }
    }

    private func resolvedSlots(
        for page: ResolvedPage,
        pageURL: URL,
        record: FavoriteRecord
    ) -> [FavoritesImageSlot] {
        page.imageURLs.enumerated().map { offset, imageURL in
            FavoritesImageSlot(
                id: "\(record.id)-p-\(pageURL.absoluteString.hashValue)-\(offset)",
                displayIndex: 0,
                pageURL: pageURL,
                pageImageIndex: offset,
                knownURL: imageURL
            )
        }
    }

    private func pruneSlots(excluding removedPageURLs: [URL]) {
        guard !removedPageURLs.isEmpty else { return }
        let removedSet = Set(removedPageURLs)
        var slots = imageSlots.filter { slot in
            guard let pageURL = slot.pageURL else { return false }
            return !removedSet.contains(pageURL)
        }
        reindex(&slots)
        imageSlots = slots
        if let selectedSlotID, slots.contains(where: { $0.id == selectedSlotID }) { return }
        selectedSlotID = slots.first?.id
    }

    /// 替换某页的全部 slot(空数组 = 移除),然后重建 displayIndex 并修复选中。
    private func replaceSlots(for pageURL: URL, with pageSlots: [FavoritesImageSlot]) {
        let slots = imageSlots
        let selectedSlot = selectedSlotID.flatMap { id in slots.first(where: { $0.id == id }) }
        let selectedIndex = selectedSlot.flatMap { s in slots.firstIndex(where: { $0.id == s.id }) }

        var newSlots: [FavoritesImageSlot] = []
        newSlots.reserveCapacity(slots.count + pageSlots.count)
        for slot in slots where slot.pageURL != pageURL {
            newSlots.append(slot)
        }

        if !pageSlots.isEmpty {
            let pageOrderByURL = Dictionary(
                uniqueKeysWithValues: knownPageURLs.enumerated().map { ($1, $0) }
            )
            guard let pageOrder = pageOrderByURL[pageURL] else { return }
            let insertAt = newSlots.firstIndex { slot in
                guard let slotPageURL = slot.pageURL,
                      let order = pageOrderByURL[slotPageURL] else { return false }
                return order > pageOrder
            } ?? newSlots.count
            newSlots.insert(contentsOf: pageSlots, at: insertAt)
        }

        // 全量重建 displayIndex：移除失败页、或两个页 URL 共享同一 pageOrder 时，
        // 部分重建会留下过期的 displayIndex，必须与数组下标恒一致。
        reindex(&newSlots)
        imageSlots = newSlots

        if let id = selectedSlotID, newSlots.contains(where: { $0.id == id }) { return }
        if let idx = selectedIndex {
            let target = min(idx, newSlots.count - 1)
            if target >= 0 { selectedSlotID = newSlots[target].id; return }
        }
        selectedSlotID = newSlots.first?.id
    }

    private func reindex(_ slots: inout [FavoritesImageSlot]) {
        for i in slots.indices {
            slots[i] = FavoritesImageSlot(
                id: slots[i].id,
                displayIndex: i,
                pageURL: slots[i].pageURL,
                pageImageIndex: slots[i].pageImageIndex,
                knownURL: slots[i].knownURL
            )
        }
    }

    private var selectedIndex: Int {
        selectedSlotID.flatMap { id in imageSlots.firstIndex { $0.id == id } } ?? 0
    }

    private var hasPendingResolution: Bool {
        knownPageURLs.contains { resolvedPages[$0] == nil }
    }

    private var selectedSlotRepresentsResolvedImage: Bool {
        guard let slot = selectedSlot else { return false }
        guard let pageURL = slot.pageURL else { return slot.knownURL != nil }
        guard let resolvedPage = resolvedPages[pageURL] else { return false }
        return resolvedPage.imageURLs.indices.contains(slot.pageImageIndex)
    }

    private func continuePendingNavigationIfNeeded() {
        guard let pendingNavigationTarget else { return }
        switch pendingNavigationTarget {
        case .afterLastImage:
            let nextIndex = selectedIndex + 1
            if imageSlots.indices.contains(nextIndex),
               isResolvedNavigableImage(at: nextIndex) {
                self.pendingNavigationTarget = nil
                selectSlot(at: nextIndex)
                return
            }
            if isResolutionComplete {
                self.pendingNavigationTarget = nil
                if !recommendations.isEmpty {
                    contentMode = .recommendations
                }
            } else {
                loadNextUnresolvedPage()
            }

        case .slot(let pageURL, let requestedImageIndex):
            guard let pageOrder = knownPageURLs.firstIndex(of: pageURL) else {
                self.pendingNavigationTarget = nil
                return
            }
            guard pageOrder < contiguousResolvedPageCount,
                  let page = resolvedPages[pageURL] else {
                loadNextUnresolvedPage()
                return
            }

            if !page.imageURLs.isEmpty {
                let imageIndex = min(requestedImageIndex, page.imageURLs.count - 1)
                guard let slot = imageSlots.first(where: {
                    $0.pageURL == pageURL && $0.pageImageIndex == imageIndex
                }) else {
                    self.pendingNavigationTarget = nil
                    return
                }
                self.pendingNavigationTarget = nil
                contentMode = .image
                selectedSlotID = slot.id
                ensureNextDetailPageLoadedIfApproachingEnd(from: slot.displayIndex)
                return
            }

            let nextPageOrder = pageOrder + 1
            guard knownPageURLs.indices.contains(nextPageOrder) else {
                self.pendingNavigationTarget = nil
                return
            }
            self.pendingNavigationTarget = .slot(
                pageURL: knownPageURLs[nextPageOrder],
                pageImageIndex: 0
            )
            loadNextUnresolvedPage()
        }
    }

    private func resumePendingResolutionFromUserAction() {
        if !failedPageURLs.isEmpty {
            failedPageURLs.removeAll()
            refreshFailureMessage()
        }
        loadNextUnresolvedPage()
    }

    func playVideo() {
        guard let context = currentVideoContext else { return }
        context.actions.play(context.record, context.url)
    }

    func saveVideoAsMP4() {
        guard let context = currentVideoContext else { return }
        context.actions.saveAsMP4(context.record, context.url)
    }

    private var currentVideoContext: (
        record: FavoriteRecord,
        url: URL,
        actions: FavoriteVideoActions
    )? {
        guard contentMode == .image,
              let record = currentRecord,
              let url = videoURL,
              let actions = sourceAdapters.adapter(for: record)?.videoActions else {
            return nil
        }
        return (record, url, actions)
    }

    private var contiguousResolvedPageCount: Int {
        var count = 0
        for pageURL in knownPageURLs {
            guard resolvedPages[pageURL] != nil else { break }
            count += 1
        }
        return count
    }

    private func isResolvedNavigableImage(at index: Int) -> Bool {
        guard imageSlots.indices.contains(index) else { return false }
        let slot = imageSlots[index]
        guard let pageURL = slot.pageURL else { return slot.knownURL != nil }
        guard let pageIndex = knownPageURLs.firstIndex(of: pageURL),
              pageIndex < contiguousResolvedPageCount,
              let page = resolvedPages[pageURL] else { return false }
        return page.imageURLs.indices.contains(slot.pageImageIndex)
    }

    private func refreshVideoURL() {
        videoURL = knownPageURLs.lazy.compactMap { self.resolvedPages[$0]?.videoURL }.first
    }

    private func refreshExternalAction() {
        externalAction = knownPageURLs.lazy.compactMap {
            self.resolvedPages[$0]?.externalAction
        }.first
    }

    private func refreshFailureMessage() {
        guard let failedIndex = knownPageURLs.firstIndex(where: failedPageURLs.contains) else {
            errorMessage = nil
            return
        }
        errorMessage = "第 \(failedIndex + 1) 页解析失败，可重试"
    }

    private func mergeRecommendations(_ incoming: [OnlineGalleryRecommendation]) {
        guard !incoming.isEmpty else { return }
        var seen = Set(recommendations.map(\.id))
        recommendations.append(contentsOf: incoming.filter { seen.insert($0.id).inserted })
    }

    private func cancelAllPageTasks() {
        for task in pageTasks.values {
            task.cancel()
        }
        pageTasks.removeAll()
        isResolving = false
    }
}

struct FavoritesImageSlot: Identifiable {
    let id: String
    let displayIndex: Int
    let pageURL: URL?
    let pageImageIndex: Int
    let knownURL: URL?
}

private extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
