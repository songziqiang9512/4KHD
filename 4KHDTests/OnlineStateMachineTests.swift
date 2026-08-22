import XCTest
@testable import _KHD

final class OnlineStateMachineTests: XCTestCase {
    @MainActor
    func testMissKonInitialResolutionHasBoundedThreePageBudget() async throws {
        let slug = UUID().uuidString
        let base = try XCTUnwrap(URL(string: "https://misskon.com/\(slug)/"))
        let pages = (1...8).map { number in
            number == 1 ? base : base.appendingPathComponent("\(number)")
        }
        let recorder = MissKonPageRecorder(pageURLs: pages)
        let store = MissKonDetailStore { url in try await recorder.resolve(url) }
        let item = makeMissKonItem(id: slug, base: base, pages: pages, imageCount: 96)

        store.prepare(item: item)
        store.resolve(item: item)

        await waitUntil { await recorder.count == 3 }
        for _ in 0..<40 { await Task.yield() }
        let requestCount = await recorder.count
        XCTAssertEqual(requestCount, 3)
        XCTAssertFalse(store.isResolutionComplete)
    }

    @MainActor
    func testMissKonSameIDNewSnapshotRebuildsDetailSlots() throws {
        let base = try XCTUnwrap(URL(string: "https://misskon.com/same-id/"))
        let page2 = base.appendingPathComponent("2")
        let store = MissKonDetailStore()
        let first = makeMissKonItem(id: "same", base: base, pages: [base], imageCount: 1)
        let refreshed = makeMissKonItem(id: "same", base: base, pages: [base, page2], imageCount: 24)

        store.prepare(item: first)
        store.prepare(item: refreshed)

        XCTAssertEqual(store.currentItem, refreshed)
        XCTAssertEqual(store.imageSlots.count, 24)
        XCTAssertEqual(store.imageSlots.last?.pageURL, page2)
    }

    @MainActor
    func testGalleryCancellationRetriesSameCursorBeforeAdvancing() async throws {
        let item = try makeGalleryItem(id: UUID().uuidString, pageCount: 3)
        let recorder = GalleryBlockingRecorder()
        let store = GalleryDetailStore { url in try await recorder.resolve(url) }
        store.prepare(for: item)

        XCTAssertTrue(store.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd))
        await waitUntil { await recorder.urls.count == 1 }
        store.cancelOutstandingDetailPageLoads()
        XCTAssertTrue(store.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd))
        await waitUntil { await recorder.urls.count == 2 }

        let calls = await recorder.urls
        XCTAssertEqual(calls, [item.pageURLs[1], item.pageURLs[1]])
        store.cancelOutstandingDetailPageLoads()
    }

    @MainActor
    func testGalleryTransientFailureCanRetrySamePage() async throws {
        let item = try makeGalleryItem(id: UUID().uuidString, pageCount: 2)
        let recorder = GalleryFailOnceRecorder(pageURLs: item.pageURLs)
        let store = GalleryDetailStore { url in try await recorder.resolve(url) }
        store.prepare(for: item)

        XCTAssertTrue(store.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd))
        await waitUntil { store.errorMessage != nil }
        XCTAssertTrue(store.ensureNextDetailPageLoaded(reason: .filmstripReachedEnd))
        await waitUntil { await recorder.urls.count == 2 }

        let calls = await recorder.urls
        XCTAssertEqual(calls, [item.pageURLs[1], item.pageURLs[1]])
    }

    @MainActor
    func testGalleryRepeatedSynthesizedPageTerminatesPagination() async throws {
        let item = try makeGalleryItem(id: "repeat", pageCount: 1)
        let next = try XCTUnwrap(URL(string: "https://www.4khd.com/?query-3-page=2"))
        let later = try XCTUnwrap(URL(string: "https://www.4khd.com/?query-3-page=3"))
        let store = GalleryFeedStore(
            sectionResolver: { _ in SiteListPage(items: [item], nextPageURL: next) },
            pageResolver: { _, _ in SiteListPage(items: [item], nextPageURL: later) }
        )

        store.refreshFromNetwork()
        await waitUntil { !store.isRefreshingList && store.allItems.count == 1 }
        store.loadMoreListIfNeeded()
        await waitUntil { !store.isRefreshingList }

        XCTAssertEqual(store.allItems.map(\.id), [item.id])
        XCTAssertFalse(store.canLoadMoreList)
    }

    @MainActor
    func testGalleryUniqueSynthesizedPageKeepsPaginationOpen() async throws {
        let first = try makeGalleryItem(id: "first", pageCount: 1)
        let second = try makeGalleryItem(id: "second", pageCount: 1)
        let next = try XCTUnwrap(URL(string: "https://www.4khd.com/?query-3-page=2"))
        let later = try XCTUnwrap(URL(string: "https://www.4khd.com/?query-3-page=3"))
        let store = GalleryFeedStore(
            sectionResolver: { _ in SiteListPage(items: [first], nextPageURL: next) },
            pageResolver: { _, _ in SiteListPage(items: [second], nextPageURL: later) }
        )

        store.refreshFromNetwork()
        await waitUntil { !store.isRefreshingList && store.allItems.count == 1 }
        store.loadMoreListIfNeeded()
        await waitUntil { !store.isRefreshingList && store.allItems.count == 2 }

        XCTAssertTrue(store.canLoadMoreList)
    }

    @MainActor
    func testWallhavenUploaderValidationAppliesExactUploaderAndPurity() throws {
        let matching = try makeWallpaper(id: "one", purity: .sfw, uploader: "Alice")
        let wrongPurity = try makeWallpaper(id: "two", purity: .nsfw, uploader: "Alice")
        let wrongUploader = try makeWallpaper(id: "three", purity: .sfw, uploader: "Mallory")

        let result = WallhavenUploaderResolver.validatedWallpapers(
            [matching, wrongPurity, wrongUploader],
            username: "alice",
            purity: .sfw
        )

        XCTAssertEqual(result.map(\.id), [matching.id])
        XCTAssertTrue(WallhavenPurity.all.allows(.nsfw))
        XCTAssertFalse(WallhavenPurity.sfw.allows(.sketchy))
    }

    @MainActor
    func testWallhavenSameIDSelectionPublishesNewSnapshot() throws {
        let suite = "4KHDTests.Wallhaven.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WallhavenFeedStore(
            accountStore: WallhavenAccountStore(),
            preferences: WallhavenContentPreferences(defaults: defaults)
        )
        let old = try makeWallpaper(id: "same", purity: .sfw, uploader: "Alice", views: 1)
        let refreshed = try makeWallpaper(id: "same", purity: .sfw, uploader: "Alice", views: 2)
        store.wallpapers = [old]
        store.selectedWallpaperID = old.id
        var published: Wallpaper?
        store.onSelectionChanged = { published = $0 }

        store.select(refreshed)

        XCTAssertEqual(published?.views, 2)
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<500 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    private func makeMissKonItem(
        id: String,
        base: URL,
        pages: [URL],
        imageCount: Int
    ) -> MissKonItem {
        MissKonItem(
            id: id,
            section: .latest,
            title: id,
            detailURL: base,
            coverURL: nil,
            coverAspectRatio: nil,
            imageCount: imageCount,
            pageCount: pages.count,
            pageURLs: pages,
            tags: []
        )
    }

    private func makeGalleryItem(id: String, pageCount: Int) throws -> GalleryItem {
        let detail = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(id).html"))
        let cover = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(id).jpg"))
        let pages = (1...pageCount).map { $0 == 1 ? detail : detail.appendingPathComponent("\($0)") }
        return GalleryItem(
            id: id,
            section: .latest,
            kind: .gallery,
            title: id,
            rawTitle: id,
            subtitle: "",
            detailURL: detail,
            coverURL: cover,
            coverAspectRatio: nil,
            imageCount: pageCount,
            pageCount: pageCount,
            pageURLs: pages,
            sampleImageURLs: [cover]
        )
    }

    private func makeWallpaper(
        id: String,
        purity: WallhavenPurity,
        uploader: String,
        views: Int = 1
    ) throws -> Wallpaper {
        Wallpaper(
            id: id,
            displayName: id,
            source: .wallhaven,
            sourcePageUrl: try XCTUnwrap(URL(string: "https://wallhaven.cc/w/\(id)")),
            sourceUrl: nil,
            thumbnailUrl: try XCTUnwrap(URL(string: "https://th.wallhaven.cc/small/\(id).jpg")),
            previewUrl: try XCTUnwrap(URL(string: "https://th.wallhaven.cc/lg/\(id).jpg")),
            fullImageUrl: try XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/\(id).jpg")),
            width: 1920,
            height: 1080,
            resolutionText: "1920x1080",
            fileSize: nil,
            fileType: "image/jpeg",
            colors: [],
            tags: [],
            createdAt: nil,
            purity: purity,
            category: nil,
            views: views,
            favorites: nil,
            uploader: uploader
        )
    }
}

private actor MissKonPageRecorder {
    private(set) var count = 0
    private let pageURLs: [URL]

    init(pageURLs: [URL]) { self.pageURLs = pageURLs }

    func resolve(_ url: URL) throws -> MissKonResolvedImagePage {
        count += 1
        return MissKonResolvedImagePage(
            pageURL: url,
            imageURLs: [URL(string: "https://cdn.misskon.com/\(count).jpg")!],
            pageURLs: pageURLs,
            mediaFireURL: nil
        )
    }
}

private actor GalleryBlockingRecorder {
    private(set) var urls: [URL] = []

    func resolve(_ url: URL) async throws -> ResolvedImagePage {
        urls.append(url)
        try await Task.sleep(for: .seconds(30))
        throw CancellationError()
    }
}

private actor GalleryFailOnceRecorder {
    private(set) var urls: [URL] = []
    private let pageURLs: [URL]

    init(pageURLs: [URL]) { self.pageURLs = pageURLs }

    func resolve(_ url: URL) throws -> ResolvedImagePage {
        urls.append(url)
        if urls.count == 1 { throw URLError(.timedOut) }
        return ResolvedImagePage(
            pageURL: url,
            imageURLs: [URL(string: "https://pic.4khd.com/resolved.jpg")!],
            pageURLs: pageURLs
        )
    }
}
