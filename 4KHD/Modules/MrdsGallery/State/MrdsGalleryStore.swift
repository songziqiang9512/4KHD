import Foundation
import Observation

@MainActor
@Observable
final class MrdsGalleryStore {
    typealias ListResolver = (MrdsListContext, Int) async throws -> MrdsListPage
    typealias DetailResolver = (URL) async throws -> MrdsResolvedDetailPage

    private(set) var filter: MrdsSection = .latest
    var searchText = ""
    private(set) var activeSearchQuery: String?
    private(set) var items: [MrdsGalleryItem] = []
    private(set) var selectedItemID: MrdsGalleryItem.ID?
    private(set) var isRefreshingList = false
    private(set) var listErrorMessage: String?
    private(set) var currentPage = 0
    private(set) var totalPages = 0
    private(set) var nextPageURL: URL?

    private(set) var imageSlots: [MrdsImageSlot] = []
    private(set) var selectedImageIndex = 0
    private(set) var detailErrorMessage: String?
    private(set) var detailMetadata: MrdsDetailMetadata?
    private(set) var videoURL: URL?
    private(set) var recommendations: [OnlineGalleryRecommendation] = []
    private(set) var detailContentMode: WorkspaceDetailContentMode = .image
    private(set) var isResolvingDetail = false

    @ObservationIgnored private let favorites: FavoritesStore
    @ObservationIgnored private let listResolver: ListResolver
    @ObservationIgnored private let detailResolver: DetailResolver
    @ObservationIgnored private var selectedItemSnapshot: MrdsGalleryItem?
    @ObservationIgnored private var preservesDetachedSelection = false
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var listRequestToken = UUID()
    @ObservationIgnored private var pendingLoadMore = false
    @ObservationIgnored private var detailGeneration = UUID()
    @ObservationIgnored private var detailTasks: [URL: Task<Void, Never>] = [:]
    @ObservationIgnored private var detailPageURLs: [URL] = []
    @ObservationIgnored private var resolvedDetailPages: [URL: [URL]] = [:]
    @ObservationIgnored private var failedDetailPages: Set<URL> = []
    @ObservationIgnored private var pendingForwardAfterLoad = false
    @ObservationIgnored private var listCache: [MrdsListContext: CachedListPage] = [:]

    private struct CachedListPage {
        var items: [MrdsGalleryItem]
        var currentPage: Int
        var totalPages: Int
        var nextPageURL: URL?
    }

    init(
        favorites: FavoritesStore,
        listResolver: @escaping ListResolver = MrdsListResolver.resolve(context:page:),
        detailResolver: @escaping DetailResolver = MrdsDetailResolver.resolve(pageURL:)
    ) {
        self.favorites = favorites
        self.listResolver = listResolver
        self.detailResolver = detailResolver
        MrdsImageDecryptor.prepare()
    }

    deinit {
        listTask?.cancel()
        detailTasks.values.forEach { $0.cancel() }
    }

    var selectedItem: MrdsGalleryItem? {
        guard let selectedItemID else { return nil }
        return items.first { $0.id == selectedItemID }
            ?? selectedItemSnapshot.flatMap { $0.id == selectedItemID ? $0 : nil }
    }

    var selectedSlot: MrdsImageSlot? {
        guard imageSlots.indices.contains(selectedImageIndex) else { return nil }
        return imageSlots[selectedImageIndex]
    }

    var canLoadMoreList: Bool {
        nextPageURL != nil
    }

    var canStepDetailBackward: Bool {
        detailContentMode == .recommendations || selectedImageIndex > 0
    }

    var canStepDetailForward: Bool {
        guard detailContentMode == .image, !imageSlots.isEmpty else { return false }
        if selectedImageIndex < imageSlots.count - 1 { return true }
        return hasPendingDetailPageWork || !recommendations.isEmpty
    }

    /// 保留旧命名，供现有调用点平滑迁移。
    var canStepImageBackward: Bool {
        canStepDetailBackward
    }

    var canStepImageForward: Bool {
        canStepDetailForward
    }

    var hasPlayableVideo: Bool {
        videoURL != nil
    }

    var hasResolvedSelectedImage: Bool {
        selectedSlotRepresentsResolvedImage
    }

    var isDetailResolutionComplete: Bool {
        !detailPageURLs.isEmpty
            && detailTasks.isEmpty
            && detailPageURLs.allSatisfy { resolvedDetailPages[$0] != nil }
    }

    var pageStatusText: String {
        guard totalPages > 0 else { return filter.title }
        return "\(filter.title) · 第 \(max(currentPage, 1))/\(totalPages) 页"
    }

    var favoriteItemIDs: Set<MrdsGalleryItem.ID> {
        Set(items.lazy.filter { self.favorites.contains(detailURL: $0.detailURL) }.map(\.id))
    }

    func bootstrapIfNeeded() {
        guard items.isEmpty, listTask == nil else { return }
        refreshFromNetwork()
    }

    func setFilter(_ filter: MrdsSection) {
        guard self.filter != filter || activeSearchQuery != nil else { return }
        preservesDetachedSelection = false
        self.filter = filter
        searchText = ""
        activeSearchQuery = nil
        restoreCachedListIfAvailable()
        refreshFromNetwork()
    }

    func submitSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearch()
            return
        }
        guard query != activeSearchQuery else { return }
        preservesDetachedSelection = false
        activeSearchQuery = query
        restoreCachedListIfAvailable()
        refresh(context: .search(query))
    }

    func clearSearch() {
        guard activeSearchQuery != nil || !searchText.isEmpty else { return }
        preservesDetachedSelection = false
        searchText = ""
        activeSearchQuery = nil
        restoreCachedListIfAvailable()
        refresh(context: .filter(filter))
    }

    func refreshFromNetwork() {
        let context = activeSearchQuery.map(MrdsListContext.search) ?? .filter(filter)
        refresh(context: context)
    }

    func retryLastFailure() {
        if listErrorMessage != nil {
            refreshFromNetwork()
        } else if let pageURL = detailPageURLs.first(where: { failedDetailPages.contains($0) }) {
            failedDetailPages.remove(pageURL)
            if failedDetailPages.isEmpty {
                detailErrorMessage = nil
            }
            resolveDetailPage(pageURL, generation: detailGeneration)
        }
    }

    func loadMoreListIfNeeded() {
        guard let nextPageURL else { return }
        guard listTask == nil else {
            pendingLoadMore = true
            return
        }
        let context = activeSearchQuery.map(MrdsListContext.search) ?? .filter(filter)
        guard let nextPage = Self.pageNumber(from: nextPageURL), nextPage > currentPage else {
            self.nextPageURL = nil
            return
        }
        startListRequest(context: context, page: nextPage, replacing: false)
    }

    func select(_ item: MrdsGalleryItem, force: Bool = false) {
        guard force || selectedItemID != item.id else { return }
        preservesDetachedSelection = false
        selectedItemSnapshot = item
        selectedItemID = item.id
        prepareDetail(for: item)
    }

    func openRecommendation(_ recommendation: OnlineGalleryRecommendation) {
        let item = MrdsGalleryItem(
            id: Self.itemID(from: recommendation.detailURL),
            title: recommendation.title,
            rawTitle: recommendation.title,
            category: "推荐图集",
            publishedDate: "",
            detailURL: recommendation.detailURL,
            coverURL: recommendation.coverURL,
            coverAspectRatio: recommendation.coverAspectRatio ?? 1.6,
            hasVideo: false
        )
        select(item, force: true)
        preservesDetachedSelection = true
    }

    func selectImage(at index: Int) {
        guard imageSlots.indices.contains(index) else { return }
        detailContentMode = .image
        pendingForwardAfterLoad = false
        selectedImageIndex = index
        prefetchDetailIfApproachingEnd()
    }

    func stepImage(_ delta: Int) {
        guard delta != 0 else { return }

        if detailContentMode == .recommendations {
            guard delta < 0 else { return }
            detailContentMode = .image
            selectedImageIndex = max(imageSlots.count - 1, 0)
            return
        }

        guard !imageSlots.isEmpty else { return }
        let target = selectedImageIndex + delta
        if imageSlots.indices.contains(target) {
            selectedImageIndex = target
            pendingForwardAfterLoad = false
            prefetchDetailIfApproachingEnd()
            return
        }

        guard delta > 0 else { return }
        if hasPendingDetailPageWork {
            // 列表封面只是详情页解析前的过渡图。若用户此时在末槽按“下一张”，
            // 先完成当前原图解析并停留展示，不能把这次操作记成越界跳转，
            // 否则单图图集会在解析完成后直接跳到相关推荐。
            guard selectedSlotRepresentsResolvedImage else {
                pendingForwardAfterLoad = false
                ensureNextDetailPageLoaded()
                return
            }
            pendingForwardAfterLoad = true
            ensureNextDetailPageLoaded()
        } else if !recommendations.isEmpty {
            detailContentMode = .recommendations
        }
    }

    func ensureNextDetailPageLoaded() {
        // 只有当前页成功后才能启动后一页。胶片条 willDisplay 可能在一次
        // 布局中连续回调多次，但不能跨过仍在途的连续页前缀。
        guard detailTasks.isEmpty else { return }
        guard let pageURL = nextLoadableDetailPageURL else { return }
        resolveDetailPage(pageURL, generation: detailGeneration)
    }

    /// 详情面板或沉浸模式真正可见时才启动 HTML/大图解析。
    /// 列表单击只准备封面状态，避免快速移动选择时反复取消并重建网络任务。
    func resolveSelectedDetailIfNeeded() {
        guard selectedItem != nil, detailContentMode == .image else { return }
        if let firstPageURL = detailPageURLs.first,
           resolvedDetailPages[firstPageURL] == nil,
           detailTasks[firstPageURL] == nil,
           !failedDetailPages.contains(firstPageURL)
        {
            resolveDetailPage(firstPageURL, generation: detailGeneration)
            return
        }
        prefetchDetailIfApproachingEnd()
    }

    func cancelDetailResolution() {
        guard !detailTasks.isEmpty else { return }
        detailTasks.values.forEach { $0.cancel() }
        detailTasks.removeAll()
        pendingForwardAfterLoad = false
        isResolvingDetail = false
    }

    func isFavorite(_ item: MrdsGalleryItem) -> Bool {
        favorites.contains(detailURL: item.detailURL)
    }

    func toggleFavorite(for item: MrdsGalleryItem) async throws {
        try await favorites.toggle(MrdsFavoritesBridge.record(from: item, metadata: detailMetadata))
    }

    private func refresh(context: MrdsListContext) {
        listTask?.cancel()
        listTask = nil
        pendingLoadMore = false
        let token = UUID()
        listRequestToken = token
        listErrorMessage = nil
        isRefreshingList = true
        startListRequest(context: context, page: 1, replacing: true, token: token)
    }

    private func startListRequest(
        context: MrdsListContext,
        page: Int,
        replacing: Bool,
        token: UUID? = nil
    ) {
        let requestToken = token ?? UUID()
        listRequestToken = requestToken
        isRefreshingList = true
        listErrorMessage = nil
        listTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await listResolver(context, page)
                guard !Task.isCancelled,
                      listRequestToken == requestToken,
                      currentListContext == context else { return }
                applyListPage(result, replacing: replacing)
            } catch {
                guard !Task.isCancelled,
                      listRequestToken == requestToken,
                      currentListContext == context else { return }
                listErrorMessage = error.localizedDescription
                finishListRequest(token: requestToken)
            }
        }
    }

    private func applyListPage(_ page: MrdsListPage, replacing: Bool) {
        applyListContents(page, replacing: replacing)
        listCache[currentListContext] = CachedListPage(
            items: items,
            currentPage: currentPage,
            totalPages: totalPages,
            nextPageURL: nextPageURL
        )
        finishListRequest(token: listRequestToken)
    }

    private func applyListContents(_ page: MrdsListPage, replacing: Bool) {
        if replacing {
            var shouldPrepareSelection = true
            items = page.items
            if let selectedItemID,
               let refreshedSelection = items.first(where: { $0.id == selectedItemID })
            {
                selectedItemSnapshot = refreshedSelection
                preservesDetachedSelection = false
            } else if preservesDetachedSelection,
                      selectedItemSnapshot?.id == selectedItemID
            {
                // 模块首次启动/后台刷新可填充 feed，但不能覆盖从推荐页打开的独立详情。
                shouldPrepareSelection = false
            } else {
                selectedItemSnapshot = items.first
                selectedItemID = items.first?.id
            }
            if let selectedItem, shouldPrepareSelection {
                prepareDetail(for: selectedItem)
            } else if selectedItem == nil {
                clearDetail()
            }
        } else {
            var existing = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { existing.insert($0.id).inserted })
            if selectedItem == nil {
                selectedItemSnapshot = items.first
                selectedItemID = items.first?.id
                if let selectedItem { prepareDetail(for: selectedItem) }
            }
        }

        currentPage = page.currentPage
        totalPages = page.totalPages
        nextPageURL = page.nextPageURL
    }

    private func restoreCachedListIfAvailable() {
        guard let cached = listCache[currentListContext], !cached.items.isEmpty else { return }
        applyListContents(
            MrdsListPage(
                items: cached.items,
                currentPage: cached.currentPage,
                totalPages: cached.totalPages,
                nextPageURL: cached.nextPageURL
            ),
            replacing: true
        )
    }

    private func finishListRequest(token: UUID) {
        guard listRequestToken == token else { return }
        listTask = nil
        isRefreshingList = false
        if pendingLoadMore {
            pendingLoadMore = false
            loadMoreListIfNeeded()
        }
    }

    private var currentListContext: MrdsListContext {
        activeSearchQuery.map(MrdsListContext.search) ?? .filter(filter)
    }

    private func prepareDetail(for item: MrdsGalleryItem) {
        detailTasks.values.forEach { $0.cancel() }
        detailTasks.removeAll()
        detailGeneration = UUID()
        detailPageURLs = [item.detailURL]
        resolvedDetailPages = [:]
        failedDetailPages = []
        detailErrorMessage = nil
        detailMetadata = nil
        videoURL = nil
        recommendations = []
        detailContentMode = .image
        isResolvingDetail = false
        pendingForwardAfterLoad = false
        selectedImageIndex = 0
        if let coverURL = item.coverURL {
            imageSlots = [MrdsImageSlot(
                id: "\(item.id)-cover",
                displayIndex: 1,
                pageURL: item.detailURL,
                knownURL: coverURL
            )]
        } else {
            imageSlots = []
        }
    }

    private func clearDetail() {
        detailTasks.values.forEach { $0.cancel() }
        detailTasks.removeAll()
        detailGeneration = UUID()
        detailPageURLs = []
        resolvedDetailPages = [:]
        failedDetailPages = []
        imageSlots = []
        selectedImageIndex = 0
        detailErrorMessage = nil
        detailMetadata = nil
        videoURL = nil
        recommendations = []
        detailContentMode = .image
        isResolvingDetail = false
        pendingForwardAfterLoad = false
    }

    private func resolveDetailPage(_ pageURL: URL, generation: UUID) {
        guard detailTasks[pageURL] == nil,
              resolvedDetailPages[pageURL] == nil,
              !failedDetailPages.contains(pageURL) else { return }
        isResolvingDetail = true
        detailTasks[pageURL] = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await detailResolver(pageURL)
                guard !Task.isCancelled, detailGeneration == generation else { return }
                detailTasks[pageURL] = nil
                failedDetailPages.remove(pageURL)
                if failedDetailPages.isEmpty {
                    detailErrorMessage = nil
                }
                if !page.pageURLs.isEmpty {
                    detailPageURLs = page.pageURLs
                }
                resolvedDetailPages[page.pageURL] = page.imageURLs
                if let metadata = page.metadata {
                    detailMetadata = metadata
                }
                if let videoURL = page.videoURL {
                    self.videoURL = videoURL
                }
                mergeRecommendations(page.recommendations)

                let oldCount = imageSlots.count
                rebuildImageSlots()
                advancePendingForwardIfPossible(previousSlotCount: oldCount)

                prefetchInitialDetailPages()
                finishDetailTransition()
            } catch {
                guard !Task.isCancelled, detailGeneration == generation else { return }
                detailTasks[pageURL] = nil
                failedDetailPages.insert(pageURL)
                detailErrorMessage = error.localizedDescription
                let oldCount = imageSlots.count
                rebuildImageSlots()
                advancePendingForwardIfPossible(previousSlotCount: oldCount)
                finishDetailTransition()
            }
        }
    }

    private func advancePendingForwardIfPossible(previousSlotCount: Int) {
        guard pendingForwardAfterLoad, imageSlots.count > previousSlotCount else { return }
        selectedImageIndex = min(previousSlotCount, imageSlots.count - 1)
        pendingForwardAfterLoad = false
    }

    private func finishDetailTransition() {
        isResolvingDetail = !detailTasks.isEmpty
        guard pendingForwardAfterLoad else { return }
        if hasPendingDetailPageWork {
            ensureNextDetailPageLoaded()
        } else {
            pendingForwardAfterLoad = false
            if !recommendations.isEmpty {
                detailContentMode = .recommendations
            }
        }
    }

    private func mergeRecommendations(_ incoming: [OnlineGalleryRecommendation]) {
        guard !incoming.isEmpty else { return }
        let filled = incoming.map { recommendation -> OnlineGalleryRecommendation in
            if recommendation.coverURL != nil { return recommendation }
            guard let item = items.first(where: { $0.detailURL.isSameDetailPath(as: recommendation.detailURL) }),
                  let coverURL = item.coverURL
            else {
                return recommendation
            }
            return OnlineGalleryRecommendation(
                title: recommendation.title,
                detailURL: recommendation.detailURL,
                coverURL: coverURL,
                coverAspectRatio: item.coverAspectRatio,
                imageCount: recommendation.imageCount
            )
        }
        var seen = Set(recommendations.map(\.id))
        recommendations.append(contentsOf: filled.filter { seen.insert($0.id).inserted })
    }

    private func rebuildImageSlots() {
        let selectedURL = selectedSlot?.knownURL
        var rebuilt: [MrdsImageSlot] = []
        for pageURL in detailPageURLs {
            if failedDetailPages.contains(pageURL) { break }
            guard let imageURLs = resolvedDetailPages[pageURL] else { break }
            for imageURL in imageURLs {
                rebuilt.append(MrdsImageSlot(
                    id: imageURL.absoluteString,
                    displayIndex: rebuilt.count + 1,
                    pageURL: pageURL,
                    knownURL: imageURL
                ))
            }
        }
        imageSlots = rebuilt
        if let selectedURL, let index = rebuilt.firstIndex(where: { $0.knownURL == selectedURL }) {
            selectedImageIndex = index
        } else {
            selectedImageIndex = min(selectedImageIndex, max(rebuilt.count - 1, 0))
        }
    }

    private func prefetchInitialDetailPages() {
        let resolvedPrefixCount = detailPageURLs.prefix {
            resolvedDetailPages[$0] != nil
        }.count
        let initialPrefixTarget = min(detailPageURLs.count, 3)
        if resolvedPrefixCount < initialPrefixTarget {
            ensureNextDetailPageLoaded()
        } else {
            prefetchDetailIfApproachingEnd()
        }
    }

    private func prefetchDetailIfApproachingEnd() {
        guard imageSlots.count - selectedImageIndex <= 5 else { return }
        ensureNextDetailPageLoaded()
    }

    private var hasPendingDetailPageWork: Bool {
        detailPageURLs.contains { pageURL in
            resolvedDetailPages[pageURL] == nil
        }
    }

    private var selectedSlotRepresentsResolvedImage: Bool {
        guard let slot = selectedSlot,
              let resolvedURLs = resolvedDetailPages[slot.pageURL] else { return false }
        return resolvedURLs.contains(slot.knownURL)
    }

    private var nextLoadableDetailPageURL: URL? {
        for pageURL in detailPageURLs {
            if resolvedDetailPages[pageURL] != nil { continue }
            // 失败页是必须由用户显式重试的连续前缀缺口，不能被当成已完成，
            // 也不能绕过它去启动后页。
            if failedDetailPages.contains(pageURL) { return nil }
            // 只允许推进当前最早的缺口。若它已在途就等待，不能绕过它继续启动
            // 更后面的分页，否则前页卡住时会把整套图集在后台链式拉完。
            return detailTasks[pageURL] == nil ? pageURL : nil
        }
        return nil
    }

    private static func pageNumber(from url: URL) -> Int? {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.first != "archives" else { return nil }
        if parts.count >= 2, parts[parts.count - 2] == "page", let value = Int(parts.last ?? ""), value >= 1 {
            return value
        }
        if parts.count >= 2, let value = Int(parts.last ?? ""), value >= 2 {
            return value
        }
        return nil
    }

    private static func itemID(from detailURL: URL) -> String {
        let components = detailURL.pathComponents.filter { $0 != "/" }
        if let archiveIndex = components.lastIndex(of: "archives"),
           components.indices.contains(archiveIndex + 1)
        {
            return components[archiveIndex + 1]
        }
        return detailURL.absoluteString
    }
}
