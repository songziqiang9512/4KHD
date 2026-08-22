import Foundation
import Observation

/// 收藏模块的详情状态:统一 slot 模型,按记录来源走对应解析器
/// (Gallery → DetailPageHTMLResolver,MissKon → MissKonDetailResolver),
/// 行为与 MissKon 详情一致:占位 slot + 渐进分页解析 + 失败页移除。
/// Wallhaven 收藏记录只有封面一张图,直接单 slot 展示,不解析。
@MainActor
@Observable
final class FavoritesDetailStore {
    private(set) var currentRecord: FavoriteRecord?
    private(set) var currentSource: FavoriteSource?
    private(set) var imageSlots: [FavoritesImageSlot] = []
    var selectedSlotID: FavoritesImageSlot.ID?
    private(set) var isResolving = false
    private(set) var resolvedPageCount = 0
    private(set) var resolvedImageCount = 0
    private(set) var errorMessage: String?

    private struct ResolvedPage {
        let imageURLs: [URL]
        let pageURLs: [URL]
    }

    private var resolvedPages: [URL: ResolvedPage] = [:]
    private var failedPageURLs = Set<URL>()
    /// All page URLs discovered so far (initial + discovered via page.pageURLs).
    private var knownPageURLs: [URL] = []
    /// Per-page in-flight tasks.
    private var pageTasks: [URL: Task<Void, Never>] = [:]

    var selectedSlot: FavoritesImageSlot? {
        guard let selectedSlotID else { return nil }
        return imageSlots.first { $0.id == selectedSlotID }
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
        resolvedPageCount = 0
        resolvedImageCount = 0
        isResolving = false
        errorMessage = nil
        imageSlots = []
        selectedSlotID = nil
        currentRecord = record
        currentSource = record.flatMap(FavoriteSource.source(for:))

        guard let record, let source = currentSource else { return }

        let pageURLs: [URL]
        let estimatedImageCount: Int
        switch source {
        case .gallery:
            guard let item = GalleryFavoritesBridge.galleryItems(from: [record]).first else { return }
            pageURLs = item.pageURLs
            estimatedImageCount = item.imageCount
        case .missKon:
            guard let item = MissKonFavoritesBridge.missKonItems(from: [record]).first else { return }
            pageURLs = item.pageURLs
            estimatedImageCount = item.imageCount
        case .wallhaven:
            // 单图:直接用封面 URL,无需解析。
            imageSlots = [FavoritesImageSlot(
                id: "\(record.id)-cover",
                displayIndex: 0,
                pageURL: nil,
                pageImageIndex: 0,
                knownURL: record.coverURL.flatMap(URL.init(string:))
            )]
            selectedSlotID = imageSlots.first?.id
            return
        }

        knownPageURLs = pageURLs
        guard !knownPageURLs.isEmpty else { return }

        // 首页缓存命中直接建立已解析页。
        if let cached = DetailPageImageCache.shared.page(for: knownPageURLs[0]) {
            resolvedPages[cached.pageURL] = ResolvedPage(imageURLs: cached.imageURLs, pageURLs: cached.pageURLs)
            reconcileKnownPageURLs(with: cached.pageURLs, requestedPageURL: cached.pageURL)
            // 缓存页不会走 merge,计数在此补上(merge 改为增量累加后)。
            resolvedImageCount = cached.imageURLs.count
        }

        // 生成占位 slot:已知图片的 slot 直接带 URL,其余等待解析填充。
        let count = max(estimatedImageCount, 1)
        var slots: [FavoritesImageSlot] = []
        let pageImageCapacity = 12
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
                knownURL: cachedImageURL ?? (globalIndex == 0 ? record.coverURL.flatMap(URL.init(string:)) : nil)
            ))
        }
        imageSlots = slots
        selectedSlotID = slots.first?.id
    }

    // MARK: - 渐进解析

    /// 开始解析首页(未缓存时),完成后预取 2 页,与 MissKon 详情相同的渐进策略。
    /// 重复调用安全。
    func resolve() {
        guard currentSource != nil,
              currentRecord != nil,
              pageTasks.isEmpty,
              !knownPageURLs.isEmpty else { return }
        if resolvedPages.keys.contains(knownPageURLs[0]) {
            // 首页已解析(缓存命中):继续加载下一页;没有可加载页时结束解析状态。
            loadNextUnresolvedPage()
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
              !resolvedPages.keys.contains(pageURL),
              !failedPageURLs.contains(pageURL) else { return }
        loadPage(pageURL)
    }

    /// 接近已解析尾部时加载下一页(与 MissKon 详情相同的阈值策略)。
    func ensureNextDetailPageLoadedIfApproachingEnd(from index: Int) {
        let maxResolved = imageSlots.lastIndex(where: { $0.knownURL != nil }) ?? 0
        guard index >= max(maxResolved - 4, 0) else { return }
        loadNextUnresolvedPage()
    }

    func retry() {
        guard currentRecord != nil else { return }
        cancelAllPageTasks()
        resolvedPages = [:]
        failedPageURLs = []
        resolvedPageCount = 0
        resolvedImageCount = 0
        errorMessage = nil
        resolve()
    }

    func cancelResolution() {
        cancelAllPageTasks()
    }

    func selectSlot(at displayIndex: Int) {
        guard imageSlots.indices.contains(displayIndex) else { return }
        selectedSlotID = imageSlots[displayIndex].id
    }

    // MARK: - 页加载

    private func loadPage(_ pageURL: URL, prefetchNext: Int = 0) {
        guard !pageTasks.keys.contains(pageURL),
              !resolvedPages.keys.contains(pageURL),
              !failedPageURLs.contains(pageURL) else { return }

        let recordID = currentRecord?.id
        pageTasks[pageURL] = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.resolvePage(pageURL)
                guard !Task.isCancelled,
                      self.currentRecord?.id == recordID,
                      self.pageTasks[pageURL] != nil else { return }
                self.reconcileKnownPageURLs(with: page.pageURLs, requestedPageURL: pageURL)
                self.resolvedPages[pageURL] = page
                self.pageTasks[pageURL] = nil
                self.mergeResolvedPage(page, pageURL: pageURL)
                if prefetchNext > 0 {
                    self.schedulePrefetch(count: prefetchNext, after: pageURL)
                }
                if self.pageTasks.isEmpty {
                    self.isResolving = false
                }
            } catch {
                guard !Task.isCancelled,
                      self.currentRecord?.id == recordID,
                      self.pageTasks[pageURL] != nil else { return }
                self.pageTasks[pageURL] = nil
                self.failedPageURLs.insert(pageURL)
                self.removeSlots(forFailedPage: pageURL)
            }
        }
        if pageTasks.count == 1 { isResolving = true }
    }

    /// 解析成功后预取接下来的若干页(每页解析完成后不继续链式加载)。
    private func schedulePrefetch(count: Int, after pageURL: URL) {
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

    private func resolvePage(_ pageURL: URL) async throws -> ResolvedPage {
        switch currentSource {
        case .gallery:
            let page = try await DetailPageHTMLResolver.resolve(pageURL: pageURL)
            return ResolvedPage(imageURLs: page.imageURLs, pageURLs: page.pageURLs)
        case .missKon:
            let page = try await MissKonDetailResolver.resolve(pageURL: pageURL)
            return ResolvedPage(imageURLs: page.imageURLs, pageURLs: page.pageURLs)
        case .wallhaven, nil:
            throw URLError(.unsupportedURL)
        }
    }

    private func loadNextUnresolvedPage() {
        guard let nextURL = knownPageURLs.first(where: {
            !resolvedPages.keys.contains($0)
                && !failedPageURLs.contains($0)
                && !pageTasks.keys.contains($0)
        }) else {
            if pageTasks.isEmpty {
                isResolving = false
            }
            return
        }
        loadPage(nextURL)
    }

    private func reconcileKnownPageURLs(with resolvedPageURLs: [URL], requestedPageURL: URL) {
        guard !resolvedPageURLs.isEmpty else { return }
        var seen = Set<URL>()
        let normalized = resolvedPageURLs
            .filter { seen.insert($0).inserted }
            .sorted { ($0.trailingPageNumber ?? 1) < ($1.trailingPageNumber ?? 1) }
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
    }

    /// 用解析结果替换该页的占位 slot。
    private func mergeResolvedPage(_ page: ResolvedPage, pageURL: URL) {
        guard let record = currentRecord else { return }
        let pageSlots: [FavoritesImageSlot] = page.imageURLs.enumerated().map { offset, imageURL in
            FavoritesImageSlot(
                id: "\(record.id)-p-\(pageURL.absoluteString.hashValue)-\(offset)",
                displayIndex: 0,
                pageURL: pageURL,
                pageImageIndex: offset,
                knownURL: imageURL
            )
        }
        replaceSlots(for: pageURL, with: pageSlots)
        errorMessage = nil
        if resolvedPages.count > 0 {
            resolvedPageCount = resolvedPages.count
            // merge 的页此前未解析(loadPage 有 resolvedPages 去重 guard),增量累加即可。
            resolvedImageCount += page.imageURLs.count
        }
    }

    /// 页解析失败:移除该页占位 slot。
    private func removeSlots(forFailedPage pageURL: URL) {
        replaceSlots(for: pageURL, with: [])
        if resolvedPages.isEmpty, pageTasks.isEmpty {
            errorMessage = "解析失败"
            isResolving = false
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
            guard let pageOrder = knownPageURLs.firstIndex(of: pageURL) else { return }
            let insertAt = newSlots.firstIndex { slot in
                guard let slotPageURL = slot.pageURL,
                      let order = knownPageURLs.firstIndex(of: slotPageURL) else { return false }
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
