@testable import _KHD
import XCTest

final class OnlineStateMachineTests: XCTestCase {
    @MainActor
    func testMissKonInitialResolutionHasBoundedThreePageBudget() async throws {
        let slug = UUID().uuidString
        let base = try XCTUnwrap(URL(string: "https://misskon.com/\(slug)/"))
        let pages = (1 ... 8).map { number in
            number == 1 ? base : base.appendingPathComponent("\(number)")
        }
        let recorder = MissKonPageRecorder(pageURLs: pages)
        let store = MissKonDetailStore { url in try await recorder.resolve(url) }
        let item = makeMissKonItem(id: slug, base: base, pages: pages, imageCount: 96)

        store.prepare(item: item)
        store.resolve(item: item)

        await waitUntil { await recorder.count == 3 }
        for _ in 0 ..< 40 {
            await Task.yield()
        }
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
    func testGalleryStepsFromLastImageToRecommendationsAndBack() throws {
        let item = try makeGalleryItem(id: "gallery-recommendations", pageCount: 1)
        let recommendation = try makeRecommendation(source: .gallery)
        let store = GalleryDetailStore()
        store.prepare(for: item)
        store.registerResolvedPage(
            ResolvedImagePage(
                pageURL: item.detailURL,
                imageURLs: item.sampleImageURLs,
                pageURLs: item.pageURLs,
                recommendations: [recommendation]
            )
        )

        XCTAssertTrue(store.canStepForward)
        store.stepImage(1)
        XCTAssertEqual(store.contentMode, .recommendations)
        XCTAssertTrue(store.canStepBackward)
        XCTAssertFalse(store.canStepForward)

        store.stepImage(-1)
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertEqual(store.selectedImageIndex, store.loadedImageSlots.count - 1)
    }

    @MainActor
    func testMissKonStepsFromLastImageToRecommendationsAndBack() async throws {
        let base = try XCTUnwrap(URL(string: "https://misskon.com/recommendations/"))
        let item = makeMissKonItem(id: "misskon-recommendations", base: base, pages: [base], imageCount: 1)
        let recommendation = try makeRecommendation(source: .missKon)
        let imageURL = try XCTUnwrap(URL(string: "https://misskon.com/media/current.jpg"))
        let store = MissKonDetailStore { url in
            MissKonResolvedImagePage(
                pageURL: url,
                imageURLs: [imageURL],
                pageURLs: [base],
                mediaFireURL: nil,
                recommendations: [recommendation]
            )
        }

        store.prepare(item: item)
        store.resolve(item: item)
        await waitUntil { store.isResolutionComplete }

        XCTAssertTrue(store.canStepForward)
        store.stepSelection(1)
        XCTAssertEqual(store.contentMode, .recommendations)
        XCTAssertTrue(store.canStepBackward)
        XCTAssertFalse(store.canStepForward)

        store.stepSelection(-1)
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertEqual(store.selectedSlotID, store.imageSlots.last?.id)
    }

    @MainActor
    func testFavoritesStepsFromLastImageToSourceRecommendationAndBack() async throws {
        let slug = UUID().uuidString
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let imageURL = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug).jpg"))
        let recommendation = try makeRecommendation(source: .gallery)
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(pageURLs: [pageURL], estimatedImageCount: 1, pageImageCapacity: 20)
                },
                resolvePage: { _ in
                    FavoriteResolvedImagePage(
                        imageURLs: [imageURL],
                        pageURLs: [pageURL],
                        recommendations: [recommendation]
                    )
                },
                configureImageRequest: { _ in }
            ),
        ])
        let record = FavoriteRecord(
            id: slug,
            sourceID: GallerySection.latest.rawValue,
            title: slug,
            rawTitle: slug,
            subtitle: "",
            detailURL: pageURL.absoluteString,
            coverURL: imageURL.absoluteString,
            imageCount: 1,
            pageCount: 1
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)
        store.resolve()
        await waitUntil { !store.isResolving && store.recommendations == [recommendation] }

        XCTAssertTrue(store.canStepForward)
        store.stepSelection(1)
        XCTAssertEqual(store.contentMode, .recommendations)
        XCTAssertTrue(store.canStepBackward)
        XCTAssertFalse(store.canStepForward)

        store.stepSelection(-1)
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertEqual(store.selectedSlotID, store.imageSlots.last?.id)
    }

    @MainActor
    func testFavoritesCoverOnlyLastSlotRequiresTwoForwardActionsBeforeRecommendations() async throws {
        let coverURL = try XCTUnwrap(URL(string: "https://pic.4khd.com/temporary-cover.jpg"))
        try await assertFavoritesUnresolvedLastSlotRequiresTwoForwardActions(coverURL: coverURL)
    }

    @MainActor
    func testFavoritesNilPlaceholderLastSlotRequiresTwoForwardActionsBeforeRecommendations() async throws {
        try await assertFavoritesUnresolvedLastSlotRequiresTwoForwardActions(coverURL: nil)
    }

    @MainActor
    func testFavoritesSingleForwardWaitsForAllRemainingPagesBeforeRecommendations() async throws {
        let slug = UUID().uuidString
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let page2 = page1.appendingPathComponent("2")
        let page3 = page1.appendingPathComponent("3")
        let page4 = page1.appendingPathComponent("4")
        let pageURLs = [page1, page2, page3, page4]
        let imageURL = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug).jpg"))
        let recommendation = try makeRecommendation(source: .gallery)
        let page2Started = expectation(description: "favorite page 2 starts")
        let page3Started = expectation(description: "favorite page 3 starts")
        let page4Started = expectation(description: "favorite page 4 starts by pending-forward relay")
        let page2Gate = AsyncStream<Void>.makeStream()
        let page3Gate = AsyncStream<Void>.makeStream()
        let page4Gate = AsyncStream<Void>.makeStream()
        defer {
            page2Gate.continuation.finish()
            page3Gate.continuation.finish()
            page4Gate.continuation.finish()
            FavoriteSourceAdapterRegistry.shared.replaceAdapters([])
        }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(pageURLs: pageURLs, estimatedImageCount: 1, pageImageCapacity: 20)
                },
                resolvePage: { pageURL in
                    switch pageURL {
                    case page2:
                        page2Started.fulfill()
                        for await _ in page2Gate.stream {
                            break
                        }
                        return FavoriteResolvedImagePage(imageURLs: [], pageURLs: pageURLs)
                    case page3:
                        page3Started.fulfill()
                        for await _ in page3Gate.stream {
                            break
                        }
                        return FavoriteResolvedImagePage(imageURLs: [], pageURLs: pageURLs)
                    case page4:
                        page4Started.fulfill()
                        for await _ in page4Gate.stream {
                            break
                        }
                        return FavoriteResolvedImagePage(imageURLs: [], pageURLs: pageURLs)
                    default:
                        return FavoriteResolvedImagePage(
                            imageURLs: [imageURL],
                            pageURLs: pageURLs,
                            recommendations: [recommendation]
                        )
                    }
                },
                configureImageRequest: { _ in }
            ),
        ])
        let record = FavoriteRecord(
            id: slug,
            sourceID: GallerySection.latest.rawValue,
            title: slug,
            rawTitle: slug,
            subtitle: "",
            detailURL: page1.absoluteString,
            coverURL: imageURL.absoluteString,
            imageCount: 1,
            pageCount: pageURLs.count
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)
        store.resolve()
        await fulfillment(of: [page2Started], timeout: 1.0)
        await waitUntil {
            store.recommendations == [recommendation]
                && store.resolvedPageCount == 1
                && store.isResolving
        }

        XCTAssertFalse(store.isResolutionComplete)
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertEqual(store.selectedSlot?.knownURL, imageURL)

        // One forward action must stay pending while prefetched pages are in flight.
        store.stepSelection(1)
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertEqual(store.selectedSlot?.knownURL, imageURL)

        // Page 3 must not start until the earlier page-2 gap closes.
        page2Gate.continuation.yield()
        page2Gate.continuation.finish()
        await fulfillment(of: [page3Started], timeout: 1.0)
        await waitUntil { store.resolvedPageCount == 2 }
        XCTAssertEqual(store.contentMode, .image)

        page3Gate.continuation.yield()
        page3Gate.continuation.finish()
        await fulfillment(of: [page4Started], timeout: 1.0)
        await waitUntil { store.resolvedPageCount == 3 }
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertFalse(store.isResolutionComplete)

        page4Gate.continuation.yield()
        page4Gate.continuation.finish()
        await waitUntil {
            store.isResolutionComplete
                && !store.isResolving
                && store.contentMode == .recommendations
        }

        XCTAssertEqual(store.resolvedPageCount, 4)
        XCTAssertEqual(store.imageSlots.map(\.knownURL), [imageURL])
        XCTAssertTrue(store.canStepBackward)
        XCTAssertFalse(store.canStepForward)

        store.stepSelection(-1)
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertEqual(store.selectedSlotID, store.imageSlots.last?.id)
        XCTAssertEqual(store.selectedSlot?.knownURL, imageURL)
    }

    @MainActor
    func testFavoritesPrefetchDoesNotStartBeyondInFlightGap() async throws {
        let slug = UUID().uuidString
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let page2 = page1.appendingPathComponent("2")
        let page3 = page1.appendingPathComponent("3")
        let page4 = page1.appendingPathComponent("4")
        let pages = [page1, page2, page3, page4]
        let image1 = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-1.jpg"))
        let image2 = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-2.jpg"))
        let image3 = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-3.jpg"))
        let page2Gate = AsyncStream<Void>.makeStream()
        let page3Gate = AsyncStream<Void>.makeStream()
        let recorder = FavoritePageRequestRecorder()
        defer {
            page2Gate.continuation.finish()
            page3Gate.continuation.finish()
            FavoriteSourceAdapterRegistry.shared.replaceAdapters([])
        }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(pageURLs: pages, estimatedImageCount: 1, pageImageCapacity: 20)
                },
                resolvePage: { url in
                    await recorder.record(url)
                    switch url {
                    case page2:
                        for await _ in page2Gate.stream {
                            break
                        }
                        return FavoriteResolvedImagePage(imageURLs: [image2], pageURLs: pages)
                    case page3:
                        for await _ in page3Gate.stream {
                            break
                        }
                        return FavoriteResolvedImagePage(imageURLs: [image3], pageURLs: pages)
                    case page4:
                        return FavoriteResolvedImagePage(imageURLs: [], pageURLs: pages)
                    default:
                        return FavoriteResolvedImagePage(imageURLs: [image1], pageURLs: pages)
                    }
                },
                configureImageRequest: { _ in }
            ),
        ])
        let record = FavoriteRecord(
            id: slug,
            sourceID: GallerySection.latest.rawValue,
            title: slug,
            rawTitle: slug,
            subtitle: "",
            detailURL: page1.absoluteString,
            coverURL: image1.absoluteString,
            imageCount: 1,
            pageCount: pages.count
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)
        store.resolve()
        await waitUntil { await recorder.urls.count == 2 }
        store.stepSelection(1)

        // Later pages must not even start while page 2 is still in flight.
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(store.selectedSlot?.knownURL, image1)
        let requestedURLsBeforeClosingGap = await recorder.urls
        XCTAssertEqual(requestedURLsBeforeClosingGap, [page1, page2])
        XCTAssertFalse(requestedURLsBeforeClosingGap.contains(page3))
        XCTAssertFalse(requestedURLsBeforeClosingGap.contains(page4))

        page2Gate.continuation.yield()
        page2Gate.continuation.finish()
        await waitUntil { await recorder.urls.contains(page3) }
        await waitUntil { store.selectedSlot?.knownURL == image2 }
        XCTAssertEqual(store.selectedSlot?.knownURL, image2)

        page3Gate.continuation.yield()
        page3Gate.continuation.finish()
    }

    @MainActor
    func testFavoritePagedAdaptersDeclareSourcePageCapacities() throws {
        let suffix = UUID().uuidString
        let galleryURL = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(suffix).html"))
        let missKonURL = try XCTUnwrap(URL(string: "https://misskon.com/\(suffix)/"))
        let wallhavenURL = try XCTUnwrap(URL(string: "https://wallhaven.cc/w/abc123"))
        let knitURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/12345/"))
        let mediaFireURL = try XCTUnwrap(URL(string: "https://ouo.io/\(suffix)"))
        defer { FavoriteSourceAdapterRegistry.shared.replaceAdapters([]) }

        WorkspaceAppAssembly.configureFavoriteSourceAdapters { _ in
            throw URLError(.unsupportedURL)
        }

        let cases: [(FavoriteSource, FavoriteRecord, Int)] = [
            (
                .gallery,
                FavoriteRecord(
                    id: "gallery-\(suffix)", sourceID: GallerySection.latest.rawValue,
                    title: suffix, rawTitle: suffix, subtitle: "", detailURL: galleryURL.absoluteString,
                    coverURL: "https://pic.4khd.com/\(suffix).jpg", imageCount: 40, pageCount: 2
                ),
                20
            ),
            (
                .missKon,
                FavoriteRecord(
                    id: "misskon-\(suffix)", sourceID: MissKonSection.latest.rawValue,
                    title: suffix, rawTitle: suffix, subtitle: "", detailURL: missKonURL.absoluteString,
                    coverURL: "https://misskon.com/media/\(suffix).jpg", imageCount: 24, pageCount: 2
                ),
                12
            ),
            (
                .wallhaven,
                FavoriteRecord(
                    id: "abc123", sourceID: "wallhaven", title: suffix, rawTitle: suffix,
                    subtitle: "1920x1080 · image/jpeg · SFW", detailURL: wallhavenURL.absoluteString,
                    coverURL: "https://th.wallhaven.cc/lg/ab/wallhaven-abc123.jpg",
                    imageCount: 1, pageCount: 1
                ),
                1
            ),
            (
                .knit,
                FavoriteRecord(
                    id: "knit:12345", sourceID: "knit", title: suffix, rawTitle: suffix,
                    subtitle: "", detailURL: knitURL.absoluteString,
                    coverURL: "https://media.knit.bid/images/12345.jpg", imageCount: 20, pageCount: 2
                ),
                10
            ),
        ]

        for (source, record, expectedCapacity) in cases {
            let content = try XCTUnwrap(
                FavoriteSourceAdapterRegistry.shared.adapter(for: source)?.detailContent(record)
            )
            guard case let .paged(_, _, capacity) = content else {
                XCTFail("\(source) should use paged favorite detail content")
                continue
            }
            XCTAssertEqual(capacity, expectedCapacity, "Unexpected capacity for \(source)")
        }

        MissKonDetailMetadataCache.shared.store(pageURL: missKonURL, mediaFireURL: mediaFireURL)
        let cachedAction = FavoriteSourceAdapterRegistry.shared
            .adapter(for: .missKon)?
            .cachedExternalAction(missKonURL)
        XCTAssertEqual(cachedAction?.title, "MediaFire 下载")
        XCTAssertEqual(cachedAction?.url, mediaFireURL)
    }

    @MainActor
    func testFavoritesCachedGalleryHomepageUsesExactTwentyImageCapacity() throws {
        let slug = UUID().uuidString
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let page2 = page1.appendingPathComponent("2")
        let cachedImages = try (0 ..< 20).map { index in
            try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-\(index).jpg"))
        }
        DetailPageImageCache.shared.store(
            pageURL: page1,
            imageURLs: cachedImages,
            pageURLs: [page1, page2],
            recommendations: []
        )
        defer { FavoriteSourceAdapterRegistry.shared.replaceAdapters([]) }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(
                        pageURLs: [page1, page2],
                        estimatedImageCount: 22,
                        pageImageCapacity: 20
                    )
                },
                resolvePage: { _ in throw URLError(.unsupportedURL) },
                configureImageRequest: { _ in }
            ),
        ])
        let record = FavoriteRecord(
            id: slug, sourceID: GallerySection.latest.rawValue, title: slug, rawTitle: slug,
            subtitle: "", detailURL: page1.absoluteString, coverURL: cachedImages[0].absoluteString,
            imageCount: 22, pageCount: 2
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)

        XCTAssertEqual(store.imageSlots.count, 22)
        XCTAssertEqual(Array(store.imageSlots.prefix(20).compactMap(\.knownURL)), cachedImages)
        XCTAssertEqual(Array(store.imageSlots.prefix(20).compactMap(\.pageURL)), Array(repeating: page1, count: 20))
        let page2Slots = store.imageSlots.filter { $0.pageURL == page2 }
        XCTAssertEqual(page2Slots.count, 2)
        XCTAssertEqual(page2Slots.map(\.pageImageIndex), [0, 1])
        XCTAssertTrue(page2Slots.allSatisfy { $0.knownURL == nil })
        XCTAssertEqual(store.resolvedPageCount, 1)
    }

    @MainActor
    func testFavoritesBoundsInitialPlaceholderWindowForPathologicalCounts() throws {
        let slug = UUID().uuidString
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let pages = (1 ... 500).map { page in
            page == 1 ? page1 : page1.appendingPathComponent("\(page)")
        }
        defer { FavoriteSourceAdapterRegistry.shared.replaceAdapters([]) }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(
                        pageURLs: pages,
                        estimatedImageCount: 10000,
                        pageImageCapacity: 20
                    )
                },
                resolvePage: { _ in throw URLError(.unsupportedURL) },
                configureImageRequest: { _ in }
            ),
        ])
        let record = FavoriteRecord(
            id: slug, sourceID: GallerySection.latest.rawValue, title: slug, rawTitle: slug,
            subtitle: "", detailURL: page1.absoluteString, coverURL: nil,
            imageCount: 10000, pageCount: 500
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)

        XCTAssertEqual(store.imageSlots.count, 1000)
        XCTAssertEqual(store.imageSlots.last?.pageURL, pages[49])
        XCTAssertTrue(store.imageSlots.allSatisfy { $0.displayIndex < 1000 })
    }

    @MainActor
    func testFavoritesFarPlaceholderAdvancesOnlyThroughContiguousPages() async throws {
        let slug = UUID().uuidString
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let pages = (0 ..< 6).map { index in
            index == 0 ? page1 : page1.appendingPathComponent("\(index + 1)")
        }
        let images = try (0 ..< 6).map { index in
            try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-\(index + 1).jpg"))
        }
        let gates = pages.map { _ in AsyncStream<Void>.makeStream() }
        let recorder = FavoritePageRequestRecorder()
        defer {
            for gate in gates {
                gate.continuation.finish()
            }
            FavoriteSourceAdapterRegistry.shared.replaceAdapters([])
        }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(pageURLs: pages, estimatedImageCount: 6, pageImageCapacity: 1)
                },
                resolvePage: { url in
                    guard let index = pages.firstIndex(of: url) else { throw URLError(.badURL) }
                    await recorder.record(url)
                    for await _ in gates[index].stream {
                        break
                    }
                    try Task.checkCancellation()
                    return FavoriteResolvedImagePage(imageURLs: [images[index]], pageURLs: pages)
                },
                configureImageRequest: { _ in }
            ),
        ])
        let crossSourceCover = try XCTUnwrap(URL(string: "https://misskon.com/media/cross-source.jpg"))
        let record = FavoriteRecord(
            id: slug, sourceID: GallerySection.latest.rawValue, title: slug, rawTitle: slug,
            subtitle: "", detailURL: page1.absoluteString, coverURL: crossSourceCover.absoluteString,
            imageCount: 6, pageCount: 6
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)
        XCTAssertNil(store.selectedSlot?.knownURL, "Cross-source cover must not seed the first slot")
        store.selectSlot(at: 5)
        await waitUntil { await recorder.urls.count == 1 }
        var requested = await recorder.urls
        XCTAssertEqual(requested, [pages[0]])

        for index in 0 ..< 5 {
            gates[index].continuation.yield()
            gates[index].continuation.finish()
            await waitUntil { await recorder.urls.count == index + 2 }
            requested = await recorder.urls
            XCTAssertEqual(requested, Array(pages.prefix(index + 2)))
            XCTAssertEqual(store.selectedSlot?.knownURL, images[0])
        }

        gates[5].continuation.yield()
        gates[5].continuation.finish()
        await waitUntil {
            store.isResolutionComplete && store.selectedSlot?.knownURL == images[5]
        }
        XCTAssertEqual(store.selectedSlot?.knownURL, images[5])
    }

    @MainActor
    func testFavoritesLaterPageFailureRetainsContentAndRetriesBeforeRecommendations() async throws {
        let slug = UUID().uuidString
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let page2 = page1.appendingPathComponent("2")
        let image1 = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-1.jpg"))
        let image2 = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-2.jpg"))
        let recommendation = try makeRecommendation(source: .gallery)
        let recorder = FavoritePageAttemptRecorder()
        defer { FavoriteSourceAdapterRegistry.shared.replaceAdapters([]) }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(
                        pageURLs: [page1, page2],
                        estimatedImageCount: 2,
                        pageImageCapacity: 1
                    )
                },
                resolvePage: { url in
                    let attempt = await recorder.record(url)
                    if url == page2, attempt == 1 { throw URLError(.timedOut) }
                    return FavoriteResolvedImagePage(
                        imageURLs: [url == page1 ? image1 : image2],
                        pageURLs: [page1, page2],
                        recommendations: url == page1 ? [recommendation] : []
                    )
                },
                configureImageRequest: { _ in }
            ),
        ])
        let record = FavoriteRecord(
            id: slug, sourceID: GallerySection.latest.rawValue, title: slug, rawTitle: slug,
            subtitle: "", detailURL: page1.absoluteString, coverURL: image1.absoluteString,
            imageCount: 2, pageCount: 2
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)
        store.resolve()
        await waitUntil { store.errorMessage != nil && !store.isResolving }

        XCTAssertEqual(store.selectedSlot?.knownURL, image1)
        XCTAssertEqual(store.imageSlots.count, 2, "Failed page placeholder must remain retryable")
        XCTAssertEqual(store.resolvedPageCount, 1)
        XCTAssertFalse(store.isResolutionComplete)
        XCTAssertEqual(store.contentMode, .image)
        XCTAssertEqual(store.errorMessage, "第 2 页解析失败，可重试")

        // A new explicit forward action is the retry entry for the failed placeholder.
        store.stepSelection(1)
        XCTAssertEqual(store.contentMode, .image)
        await waitUntil {
            store.isResolutionComplete
                && store.errorMessage == nil
                && store.selectedSlot?.knownURL == image2
        }
        let page2AttemptCount = await recorder.attemptCount(for: page2)
        XCTAssertEqual(page2AttemptCount, 2)

        store.stepSelection(1)
        XCTAssertEqual(store.contentMode, .recommendations)
    }

    @MainActor
    func testFavoritesExternalActionUsesEarliestResolvedPageAndClearsOnSourceSwitch() async throws {
        let slug = UUID().uuidString
        let page1 = try XCTUnwrap(URL(string: "https://misskon.com/\(slug)/"))
        let page2 = page1.appendingPathComponent("2")
        let page3 = page1.appendingPathComponent("3")
        let pages = [page1, page2, page3]
        let images = try (0 ..< 3).map { index in
            try XCTUnwrap(URL(string: "https://misskon.com/media/\(slug)-\(index + 1).jpg"))
        }
        let page2Action = try FavoriteDetailExternalAction(
            title: "MediaFire 下载",
            url: XCTUnwrap(URL(string: "https://ouo.io/\(slug)-2"))
        )
        let page3Action = try FavoriteDetailExternalAction(
            title: "MediaFire 下载",
            url: XCTUnwrap(URL(string: "https://ouo.io/\(slug)-3"))
        )
        let page2Gate = AsyncStream<Void>.makeStream()
        let galleryPage = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        defer {
            page2Gate.continuation.finish()
            FavoriteSourceAdapterRegistry.shared.replaceAdapters([])
        }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .missKon,
                detailContent: {
                    _ in .paged(pageURLs: pages, estimatedImageCount: 3, pageImageCapacity: 1)
                },
                resolvePage: { url in
                    guard let index = pages.firstIndex(of: url) else { throw URLError(.badURL) }
                    if url == page2 {
                        for await _ in page2Gate.stream {
                            break
                        }
                    }
                    return FavoriteResolvedImagePage(
                        imageURLs: [images[index]],
                        pageURLs: pages,
                        externalAction: url == page2 ? page2Action : (url == page3 ? page3Action : nil)
                    )
                },
                configureImageRequest: { _ in }
            ),
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(pageURLs: [galleryPage], estimatedImageCount: 1, pageImageCapacity: 20)
                },
                resolvePage: { _ in
                    FavoriteResolvedImagePage(imageURLs: [], pageURLs: [galleryPage])
                },
                configureImageRequest: { _ in }
            ),
        ])
        let missKonRecord = FavoriteRecord(
            id: "misskon-\(slug)", sourceID: MissKonSection.latest.rawValue,
            title: slug, rawTitle: slug, subtitle: "", detailURL: page1.absoluteString,
            coverURL: images[0].absoluteString, imageCount: 3, pageCount: 3
        )
        let galleryRecord = FavoriteRecord(
            id: "gallery-\(slug)", sourceID: GallerySection.latest.rawValue,
            title: slug, rawTitle: slug, subtitle: "", detailURL: galleryPage.absoluteString,
            coverURL: nil, imageCount: 1, pageCount: 1
        )
        let store = FavoritesDetailStore()

        store.prepare(record: missKonRecord)
        store.resolve()
        await waitUntil { store.resolvedPageCount == 1 && store.isResolving }
        XCTAssertNil(store.externalAction)

        page2Gate.continuation.yield()
        page2Gate.continuation.finish()
        await waitUntil { store.externalAction == page2Action && store.isResolutionComplete }
        XCTAssertEqual(store.externalAction, page2Action)

        store.prepare(record: galleryRecord)
        XCTAssertEqual(store.currentSource, .gallery)
        XCTAssertNil(store.externalAction)
    }

    @MainActor
    func testFavoritesPublishesSourceNeutralVideoActionsAndClearsOnSwitch() async throws {
        let knitPage = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/12345/"))
        let knitImage = try XCTUnwrap(URL(string: "https://media.knit.bid/images/12345.jpg"))
        let videoURL = try XCTUnwrap(URL(string: "https://media.knit.bid/play/12345.m3u8"))
        let galleryPage = try XCTUnwrap(URL(string: "https://www.4khd.com/content/other.html"))
        let galleryImage = try XCTUnwrap(URL(string: "https://pic.4khd.com/other.jpg"))
        let actionsRecorder = FavoriteVideoActionsRecorder()
        defer { FavoriteSourceAdapterRegistry.shared.replaceAdapters([]) }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .knit,
                detailContent: {
                    _ in .paged(pageURLs: [knitPage], estimatedImageCount: 1, pageImageCapacity: 10)
                },
                resolvePage: { _ in
                    FavoriteResolvedImagePage(
                        imageURLs: [knitImage],
                        pageURLs: [knitPage],
                        videoURL: videoURL
                    )
                },
                configureImageRequest: { _ in },
                videoActions: FavoriteVideoActions(
                    play: { actionsRecorder.played.append(($0, $1)) },
                    saveAsMP4: { actionsRecorder.saved.append(($0, $1)) }
                )
            ),
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(pageURLs: [galleryPage], estimatedImageCount: 1, pageImageCapacity: 20)
                },
                resolvePage: { _ in
                    FavoriteResolvedImagePage(imageURLs: [galleryImage], pageURLs: [galleryPage])
                },
                configureImageRequest: { _ in }
            ),
        ])
        let knitRecord = FavoriteRecord(
            id: "knit:12345", sourceID: "knit", title: "Video", rawTitle: "Video", subtitle: "",
            detailURL: knitPage.absoluteString, coverURL: knitImage.absoluteString, imageCount: 1, pageCount: 1
        )
        let galleryRecord = FavoriteRecord(
            id: "gallery-other", sourceID: GallerySection.latest.rawValue, title: "Other", rawTitle: "Other",
            subtitle: "", detailURL: galleryPage.absoluteString, coverURL: galleryImage.absoluteString,
            imageCount: 1, pageCount: 1
        )
        let store = FavoritesDetailStore()

        store.prepare(record: knitRecord)
        store.resolve()
        await waitUntil { store.videoURL == videoURL && store.isResolutionComplete }
        XCTAssertTrue(store.canPlayVideo)
        XCTAssertTrue(store.canSaveVideo)
        store.playVideo()
        store.saveVideoAsMP4()
        XCTAssertEqual(actionsRecorder.played.count, 1)
        XCTAssertEqual(actionsRecorder.played.first?.0, knitRecord)
        XCTAssertEqual(actionsRecorder.played.first?.1, videoURL)
        XCTAssertEqual(actionsRecorder.saved.count, 1)

        // A running download must not disable other video records; the shared
        // DownloadStore owns duplicate suppression and serial queueing.
        XCTAssertTrue(store.canSaveVideo)
        store.saveVideoAsMP4()
        XCTAssertEqual(actionsRecorder.saved.count, 2)

        store.prepare(record: galleryRecord)
        XCTAssertNil(store.videoURL)
        XCTAssertFalse(store.canPlayVideo)
        XCTAssertFalse(store.canSaveVideo)
    }

    @MainActor
    func testFavoritesSwitchingFromPagedRecordToWallhavenResolvesOriginalImage() async throws {
        let galleryPageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/content/paged.html"))
        let galleryCoverURL = try XCTUnwrap(URL(string: "https://pic.4khd.com/paged.jpg"))
        let wallhavenDetailURL = try XCTUnwrap(URL(string: "https://wallhaven.cc/w/abcd12"))
        let wallhavenCoverURL = try XCTUnwrap(URL(string: "https://th.wallhaven.cc/lg/ab/wallhaven-abcd12.jpg"))
        let wallhavenOriginalURL = try XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/ab/wallhaven-abcd12.jpg"))
        let uploaderURL = try XCTUnwrap(URL(string: "https://wallhaven.cc/user/alice"))
        let resolvedMetadata = FavoriteDetailMetadata(
            title: "Wallhaven abcd12",
            detailText: "3840x2160 · 12.4 MB · PNG · 分类：人物 · portrait, night",
            sourceTitle: "来源: Wallhaven",
            sourceURL: wallhavenDetailURL,
            secondaryTitle: "alice 的作品",
            secondaryURL: uploaderURL,
            supportsDesktopWallpaper: true
        )
        let wallhavenResolutionRecorder = WallhavenOriginalResolutionRecorder(originalURL: wallhavenOriginalURL)
        WorkspaceAppAssembly.configureFavoriteSourceAdapters { url in
            let imageURL = await wallhavenResolutionRecorder.resolve(url)
            return FavoriteResolvedImagePage(
                imageURLs: [imageURL],
                pageURLs: [url],
                metadata: resolvedMetadata
            )
        }
        defer { FavoriteSourceAdapterRegistry.shared.replaceAdapters([]) }

        let galleryRecord = FavoriteRecord(
            id: "paged",
            sourceID: GallerySection.latest.rawValue,
            title: "Paged",
            rawTitle: "Paged",
            subtitle: "",
            detailURL: galleryPageURL.absoluteString,
            coverURL: galleryCoverURL.absoluteString,
            imageCount: 1,
            pageCount: 1
        )
        let wallhavenRecord = FavoriteRecord(
            id: "abcd12",
            sourceID: "wallhaven",
            title: "Wallhaven abcd12",
            rawTitle: "abcd12",
            subtitle: "1920x1080 · image/jpeg · SFW",
            detailURL: wallhavenDetailURL.absoluteString,
            coverURL: wallhavenCoverURL.absoluteString,
            imageCount: 1,
            pageCount: 1
        )
        let store = FavoritesDetailStore()

        store.prepare(record: galleryRecord)
        store.prepare(record: wallhavenRecord)
        XCTAssertEqual(store.selectedSlot?.knownURL, wallhavenCoverURL)
        XCTAssertEqual(store.detailMetadata?.title, "Wallhaven abcd12")
        XCTAssertEqual(store.detailMetadata?.detailText, "1920x1080 · JPEG")
        XCTAssertTrue(store.detailMetadata?.supportsDesktopWallpaper == true)
        store.resolve()
        await waitUntil { store.imageSlots.first?.knownURL == wallhavenOriginalURL }

        XCTAssertEqual(store.currentSource, .wallhaven)
        XCTAssertEqual(store.imageSlots.count, 1)
        XCTAssertEqual(store.selectedSlot?.knownURL, wallhavenOriginalURL)
        XCTAssertEqual(store.detailMetadata, resolvedMetadata)
        XCTAssertFalse(store.isResolving)
        XCTAssertNil(store.errorMessage)
        let resolvedURLs = await wallhavenResolutionRecorder.urls
        XCTAssertEqual(resolvedURLs, [wallhavenDetailURL])
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
    func testGalleryRefreshKeepsOffFeedRecommendationSelected() async throws {
        let feedItem = try makeGalleryItem(id: "feed", pageCount: 1)
        let recommendationItem = try makeGalleryItem(id: "recommendation", pageCount: 1)
        let store = GalleryFeedStore(
            sectionResolver: { _ in SiteListPage(items: [feedItem], nextPageURL: nil) }
        )

        store.refreshFromNetwork()
        await waitUntil { !store.isRefreshingList && store.selectedItem?.id == feedItem.id }
        store.select(recommendationItem)
        store.refreshFromNetwork()
        await waitUntil { !store.isRefreshingList }

        XCTAssertEqual(store.selectedItem?.id, recommendationItem.id)
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
    private func assertFavoritesUnresolvedLastSlotRequiresTwoForwardActions(
        coverURL: URL?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let slug = UUID().uuidString
        let pageURL = try XCTUnwrap(URL(string: "https://www.4khd.com/content/\(slug).html"))
        let resolvedImageURL = try XCTUnwrap(URL(string: "https://pic.4khd.com/\(slug)-original.jpg"))
        let recommendation = try makeRecommendation(source: .gallery)
        let pageStarted = expectation(description: "favorite unresolved last slot starts resolving")
        pageStarted.assertForOverFulfill = true
        let pageGate = AsyncStream<Void>.makeStream()
        defer {
            pageGate.continuation.finish()
            FavoriteSourceAdapterRegistry.shared.replaceAdapters([])
        }
        FavoriteSourceAdapterRegistry.shared.replaceAdapters([
            FavoriteSourceAdapter(
                source: .gallery,
                detailContent: {
                    _ in .paged(pageURLs: [pageURL], estimatedImageCount: 1, pageImageCapacity: 20)
                },
                resolvePage: { _ in
                    pageStarted.fulfill()
                    for await _ in pageGate.stream {
                        break
                    }
                    return FavoriteResolvedImagePage(
                        imageURLs: [resolvedImageURL],
                        pageURLs: [pageURL],
                        recommendations: [recommendation]
                    )
                },
                configureImageRequest: { _ in }
            ),
        ])
        let record = FavoriteRecord(
            id: slug,
            sourceID: GallerySection.latest.rawValue,
            title: slug,
            rawTitle: slug,
            subtitle: "",
            detailURL: pageURL.absoluteString,
            coverURL: coverURL?.absoluteString,
            imageCount: 1,
            pageCount: 1
        )
        let store = FavoritesDetailStore()

        store.prepare(record: record)
        XCTAssertEqual(store.imageSlots.count, 1, file: file, line: line)
        XCTAssertEqual(store.selectedSlot?.knownURL, coverURL, file: file, line: line)
        XCTAssertFalse(store.hasResolvedSelectedImage, file: file, line: line)
        XCTAssertFalse(store.isResolutionComplete, file: file, line: line)
        XCTAssertFalse(store.isResolving, file: file, line: line)
        XCTAssertTrue(store.canStepForward, file: file, line: line)

        // This first action only resolves the selected placeholder/temporary cover.
        store.stepSelection(1)
        await fulfillment(of: [pageStarted], timeout: 1.0)
        XCTAssertTrue(store.isResolving, file: file, line: line)
        XCTAssertEqual(store.contentMode, .image, file: file, line: line)
        XCTAssertEqual(store.selectedSlot?.knownURL, coverURL, file: file, line: line)

        pageGate.continuation.yield()
        pageGate.continuation.finish()
        await waitUntil {
            store.isResolutionComplete
                && !store.isResolving
                && store.recommendations == [recommendation]
                && store.selectedSlot?.knownURL == resolvedImageURL
        }

        XCTAssertEqual(store.contentMode, .image, file: file, line: line)
        XCTAssertEqual(store.selectedSlot?.knownURL, resolvedImageURL, file: file, line: line)
        XCTAssertTrue(store.hasResolvedSelectedImage, file: file, line: line)
        XCTAssertTrue(store.canStepForward, file: file, line: line)

        // The now-resolved final image requires a distinct second action to show recommendations.
        store.stepSelection(1)
        XCTAssertEqual(store.contentMode, .recommendations, file: file, line: line)
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0 ..< 500 {
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
        let pages = (1 ... pageCount).map { $0 == 1 ? detail : detail.appendingPathComponent("\($0)") }
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
        try Wallpaper(
            id: id,
            displayName: id,
            source: .wallhaven,
            sourcePageUrl: XCTUnwrap(URL(string: "https://wallhaven.cc/w/\(id)")),
            sourceUrl: nil,
            thumbnailUrl: XCTUnwrap(URL(string: "https://th.wallhaven.cc/small/\(id).jpg")),
            previewUrl: XCTUnwrap(URL(string: "https://th.wallhaven.cc/lg/\(id).jpg")),
            fullImageUrl: XCTUnwrap(URL(string: "https://w.wallhaven.cc/full/\(id).jpg")),
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

    private func makeRecommendation(source: OnlineSourcePolicy.Source) throws -> OnlineGalleryRecommendation {
        let detailURL: URL
        let coverURL: URL
        switch source {
        case .gallery:
            detailURL = try XCTUnwrap(URL(string: "https://www.4khd.com/content/related.html"))
            coverURL = try XCTUnwrap(URL(string: "https://pic.4khd.com/related.jpg"))
        case .missKon:
            detailURL = try XCTUnwrap(URL(string: "https://misskon.com/related/"))
            coverURL = try XCTUnwrap(URL(string: "https://misskon.com/media/related.jpg"))
        case .wallhaven, .knit, .mrds, .quanji, .porny, .tangxin:
            throw XCTSkip("Source is not part of related gallery navigation")
        }
        return OnlineGalleryRecommendation(
            title: "Related",
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: nil,
            imageCount: 1
        )
    }
}

private actor WallhavenOriginalResolutionRecorder {
    private(set) var urls: [URL] = []
    private let originalURL: URL

    init(originalURL: URL) {
        self.originalURL = originalURL
    }

    func resolve(_ pageURL: URL) -> URL {
        urls.append(pageURL)
        return originalURL
    }
}

private actor MissKonPageRecorder {
    private(set) var count = 0
    private let pageURLs: [URL]

    init(pageURLs: [URL]) {
        self.pageURLs = pageURLs
    }

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

    init(pageURLs: [URL]) {
        self.pageURLs = pageURLs
    }

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

private actor FavoritePageRequestRecorder {
    private(set) var urls: [URL] = []

    func record(_ url: URL) {
        urls.append(url)
    }
}

private actor FavoritePageAttemptRecorder {
    private var attempts: [URL: Int] = [:]

    func record(_ url: URL) -> Int {
        attempts[url, default: 0] += 1
        return attempts[url, default: 0]
    }

    func attemptCount(for url: URL) -> Int {
        attempts[url, default: 0]
    }
}

@MainActor
private final class FavoriteVideoActionsRecorder {
    var played: [(FavoriteRecord, URL)] = []
    var saved: [(FavoriteRecord, URL)] = []
}
