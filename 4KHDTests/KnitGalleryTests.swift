@testable import _KHD
import AVFoundation
import XCTest

final class KnitGalleryTests: XCTestCase {
    @MainActor
    func testCloudflareChallengeWaiterCancellationStopsAndCanRestartSession() async {
        let firstStarted = expectation(description: "first challenge session starts")
        let secondStarted = expectation(description: "second challenge session starts")
        var startCount = 0
        let bootstrapper = KnitWebSessionBootstrapper {
            startCount += 1
            if startCount == 1 {
                firstStarted.fulfill()
            } else {
                secondStarted.fulfill()
            }
        }

        let firstTask = Task { @MainActor in
            try await bootstrapper.prepare()
        }
        await fulfillment(of: [firstStarted], timeout: 1.0)
        firstTask.cancel()
        do {
            _ = try await firstTask.value
            XCTFail("Cancelled challenge waiter unexpectedly succeeded")
        } catch is CancellationError {
            // Expected: cancellation removes and resumes only this waiter.
        } catch {
            XCTFail("Unexpected cancellation error: \(error)")
        }

        let secondTask = Task { @MainActor in
            try await bootstrapper.prepare()
        }
        await fulfillment(of: [secondStarted], timeout: 1.0)
        secondTask.cancel()
        do {
            _ = try await secondTask.value
            XCTFail("Restarted challenge waiter unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected restart cancellation error: \(error)")
        }
        XCTAssertEqual(startCount, 2)
    }

    @MainActor
    func testSidebarSectionsHaveExpectedOrderTitlesAndDefaults() {
        let sections = KnitSidebarSection.allCases
        let titles = sections.map { $0.title }
        let defaults = sections.map { $0.defaultFilter }
        XCTAssertEqual(
            sections,
            [.recentUpdates, .girls, .rankings, .video]
        )
        XCTAssertEqual(
            titles,
            ["最近更新", "妹子图", "排行榜", "影片花絮"]
        )
        XCTAssertEqual(
            defaults,
            [.all, .stockings, .popular, .behindTheScenes]
        )
    }

    @MainActor
    func testGirlRankingAndLegacyRouteCatalogs() {
        let girlTypes = KnitBrowseFilter.girlTypes
        let rankingFilters = KnitBrowseFilter.rankingFilters
        let legacyLatest = KnitBrowseFilter.filter(forRouteItemID: "latest")
        let legacyPopular = KnitBrowseFilter.filter(forRouteItemID: "popular")
        let legacyVideo = KnitBrowseFilter.filter(forRouteItemID: "video")
        let topic = KnitBrowseFilter.filter(forRouteItemID: KnitBrowseFilter.topicWhiteSilkStockings.rawValue)
        let unknown = KnitBrowseFilter.filter(forRouteItemID: "unknown")
        XCTAssertEqual(
            girlTypes,
            [.sexy, .pure, .stockings, .legs, .bust, .cosplay, .uniform, .internet, .uncensored, .ai]
        )
        XCTAssertEqual(
            rankingFilters,
            [.newest, .popular, .daily, .threeDays, .weekly, .monthly]
        )

        XCTAssertEqual(legacyLatest, KnitBrowseFilter.all)
        XCTAssertEqual(legacyPopular, KnitBrowseFilter.popular)
        XCTAssertEqual(legacyVideo, KnitBrowseFilter.behindTheScenes)
        XCTAssertEqual(topic, KnitBrowseFilter.topicWhiteSilkStockings)
        XCTAssertNil(unknown)
    }

    @MainActor
    func testListRoutesUseSitePaginationProtocol() {
        XCTAssertEqual(
            KnitListContext.filter(.all).pageURL(page: 1)?.absoluteString,
            "https://xx.knit.bid/?ajax=1"
        )
        XCTAssertEqual(
            KnitListContext.filter(.cosplay).pageURL(page: 3)?.absoluteString,
            "https://xx.knit.bid/type/6/page/3/?ajax=1"
        )
        XCTAssertEqual(
            KnitListContext.filter(.monthly).pageURL(page: 2)?.absoluteString,
            "https://xx.knit.bid/rankings/monthly/page/2/?ajax=1"
        )
        XCTAssertEqual(
            KnitListContext.search("white silk").pageURL(page: 2)?.absoluteString,
            "https://xx.knit.bid/search/page/2/?s=white%20silk&ajax=1"
        )
        XCTAssertEqual(
            KnitListContext.filter(.topicWhiteSilkStockings).pageURL(page: 2)?.absoluteString,
            "https://xx.knit.bid/topic/white-silk-stockings/page/2/?ajax=1"
        )
    }

    @MainActor
    func testAJAXListParsesImageAndVideoCards() throws {
        let html = #"""
        <article class="excerpt excerpt-c4">
          <a href="/type/6/" class="imgbox-a" title="Cosplay">Cosplay</a>
          <a class="imgbox imgbox-link" href="/article/32463/" title="Test 32P 2G 1V">
            <img class="imgbox-img" src="/static/zde/timg.gif" width="300" height="200"
                 data-original-src="/static/images/test/__cover.jpg?v=1">
            <span class="play-icon"></span>
          </a>
          <h2><a>Test 32P 2G 1V</a></h2>
          <hot>1,234</hot><time>2026-08-27</time>
        </article>
        """#
        let payload: [String: Any] = [
            "html": html,
            "pagination": ["current_page": 1, "total_pages": 13, "has_next": true, "next_page": 2],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let page = try KnitListResolver.parse(data: data, context: .filter(.behindTheScenes))

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "32463")
        XCTAssertEqual(page.items[0].category, "Cosplay")
        XCTAssertEqual(page.items[0].viewCount, 1234)
        XCTAssertEqual(page.items[0].estimatedImageCount, 30)
        XCTAssertEqual(page.items[0].reportedVideoCount, 1)
        XCTAssertEqual(page.nextPageURL?.path, "/bits-of-news/page/2")
    }

    @MainActor
    func testAJAXListParsesAdjacentPhotoAndVideoCounts() throws {
        let html = Self.cardHTML(id: "74017", title: "Adjacent counts 74P17V")
        let payload: [String: Any] = [
            "html": html,
            "pagination": ["current_page": 1, "total_pages": 1, "has_next": false],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let page = try KnitListResolver.parse(data: data, context: .filter(.all))

        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].reportedPhotoCount, 74)
        XCTAssertEqual(page.items[0].reportedGIFCount, 0)
        XCTAssertEqual(page.items[0].reportedVideoCount, 17)
        XCTAssertEqual(page.items[0].estimatedImageCount, 74)
    }

    @MainActor
    func testDetailParsesImagesPagesMetadataAndHLS() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/32463/"))
        let html = #"""
        <meta property="og:description" content="Test &amp; gallery">
        <script type="application/ld+json">
        {"numberOfItems":21,"keywords":"Cosplay, Video","contentUrl":"https:\/\/media.knit.bid\/play\/abc123.m3u8"}
        </script>
        <script>window.articleConfig={"total_pages":3}</script>
        <img class="item-image__img" data-src="/static/images/test/01.jpg">
        <img class="item-image__img" src="https://r2-media.knit.bid/test/02.jpg">
        """#

        let result = try KnitDetailResolver.parseFirstPage(html: html, pageURL: pageURL)

        XCTAssertEqual(result.imageURLs.map(\.absoluteString), [
            "https://xx.knit.bid/static/images/test/01.jpg",
            "https://r2-media.knit.bid/test/02.jpg",
        ])
        XCTAssertEqual(result.pageURLs.count, 3)
        XCTAssertEqual(result.pageURLs.last?.path, "/article/32463/page/3")
        XCTAssertEqual(result.videoURL?.absoluteString, "https://media.knit.bid/play/abc123.m3u8")
        XCTAssertEqual(result.metadata?.totalImages, 21)
        XCTAssertEqual(result.metadata?.tags, ["Cosplay", "Video"])
    }

    @MainActor
    func testDetailRejectsUnreasonablePaginationAndClampsReportedImageCount() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/32463/"))
        let excessivePages = #"""
        <script>window.articleConfig={"total_pages":501}</script>
        <img class="item-image__img" data-src="/static/images/test/01.jpg">
        """#

        XCTAssertThrowsError(
            try KnitDetailResolver.parseFirstPage(html: excessivePages, pageURL: pageURL)
        ) { error in
            XCTAssertEqual(error as? KnitDetailResolverError, .unreasonablePagination)
        }

        let excessiveImageCount = #"""
        <script type="application/ld+json">{"numberOfItems":999999}</script>
        <script>window.articleConfig={"total_pages":1}</script>
        <img class="item-image__img" data-src="/static/images/test/01.jpg">
        """#
        let result = try KnitDetailResolver.parseFirstPage(html: excessiveImageCount, pageURL: pageURL)
        XCTAssertEqual(result.metadata?.totalImages, KnitDetailResolver.maximumDetailImageCount)
    }

    @MainActor
    func testDetailRecommendationsAreScopedDeduplicatedAndSourceValidated() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/32463/"))
        let outside = Self.cardHTML(id: "700", title: "Outside 7P")
        let current = Self.cardHTML(id: "32463", title: "Current 32P")
        let accepted = Self.cardHTML(id: "701", title: "Accepted 74P17V")
        let duplicate = Self.cardHTML(id: "701", title: "Duplicate 99P")
        let evil = #"""
        <article class="excerpt">
          <a class="imgbox imgbox-link" href="https://knit.bid.evil.example/article/702/">
            <img class="imgbox-img" data-original-src="https://knit.bid.evil.example/cover.jpg">
          </a>
          <h2><a>Evil 12P</a></h2>
        </article>
        """#
        let html = #"""
        <script>window.articleConfig={"total_pages":1}</script>
        <img class="item-image__img" data-src="/static/images/current/01.jpg">
        \#(outside)
        <div id="recommend-container">
          <div class="excerpts">
            \#(current)
            \#(accepted)
            \#(duplicate)
            \#(evil)
          </div>
        </div>
        """#

        let result = try KnitDetailResolver.parseFirstPage(html: html, pageURL: pageURL)

        XCTAssertEqual(result.recommendations.count, 1)
        XCTAssertEqual(result.recommendations[0].title, "Accepted 74P17V")
        XCTAssertEqual(result.recommendations[0].detailURL.absoluteString, "https://xx.knit.bid/article/701/")
        XCTAssertEqual(result.recommendations[0].imageCount, 74)
    }

    func testKnitPolicyAllowsOnlyHTTPSKnitHosts() throws {
        let detail = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/1/"))
        let playlist = try XCTUnwrap(URL(string: "https://media.knit.bid/play/test.m3u8"))
        let segment = try XCTUnwrap(URL(string: "https://r2-media.knit.bid/play/segment.ts"))
        let lookalike = try XCTUnwrap(URL(string: "https://knit.bid.evil.example/article/1/"))
        let insecure = try XCTUnwrap(URL(string: "http://xx.knit.bid/article/1/"))

        XCTAssertTrue(OnlineSourcePolicy.allows(detail, source: .knit, resource: .html))
        XCTAssertTrue(OnlineSourcePolicy.allows(playlist, source: .knit, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(segment, source: .knit, resource: .media))
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: playlist), .knit)
        XCTAssertFalse(OnlineSourcePolicy.allows(lookalike, source: .knit, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(insecure, source: .knit, resource: .html))
    }

    func testHLSMediaPlaylistResolvesOrderedTrustedSegments() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://media.knit.bid/play/video.m3u8"))
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXTINF:4.0,
        segment-001.ts
        #EXTINF:5.0,
        https://r2-media.knit.bid/play/segment-002.ts
        #EXT-X-ENDLIST
        """

        let parsed = try KnitHLSPlaylist.parse(playlist, baseURL: baseURL)

        guard case let .media(segments) = parsed else {
            return XCTFail("Expected a media playlist")
        }
        XCTAssertEqual(segments.map(\.url.absoluteString), [
            "https://media.knit.bid/play/segment-001.ts",
            "https://r2-media.knit.bid/play/segment-002.ts",
        ])
        XCTAssertTrue(segments.allSatisfy { $0.encryption == nil })
    }

    func testHLSMasterPlaylistChoosesHighestBandwidthFirst() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://media.knit.bid/play/master.m3u8"))
        let playlist = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=800000
        low/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3200000
        high/index.m3u8
        """

        let parsed = try KnitHLSPlaylist.parse(playlist, baseURL: baseURL)

        guard case let .master(variants) = parsed else {
            return XCTFail("Expected a master playlist")
        }
        XCTAssertEqual(variants.map(\.bandwidth), [3_200_000, 800_000])
        XCTAssertEqual(variants.first?.url.absoluteString, "https://media.knit.bid/play/high/index.m3u8")
    }

    func testHLSPlaylistRejectsUnsupportedEncryptionLiveAndUntrustedSegments() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://media.knit.bid/play/video.m3u8"))
        let sampleAES = """
        #EXTM3U
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="key.bin"
        #EXTINF:4.0,
        segment.ts
        #EXT-X-ENDLIST
        """
        let live = """
        #EXTM3U
        #EXTINF:4.0,
        segment.ts
        """
        let untrusted = """
        #EXTM3U
        #EXTINF:4.0,
        https://knit.bid.evil.example/segment.ts
        #EXT-X-ENDLIST
        """

        XCTAssertThrowsError(try KnitHLSPlaylist.parse(sampleAES, baseURL: baseURL)) { error in
            XCTAssertEqual(error as? KnitVideoDownloadError, .encryptedPlaylist)
        }
        XCTAssertThrowsError(try KnitHLSPlaylist.parse(live, baseURL: baseURL)) { error in
            XCTAssertEqual(error as? KnitVideoDownloadError, .livePlaylist)
        }
        XCTAssertThrowsError(try KnitHLSPlaylist.parse(untrusted, baseURL: baseURL)) { error in
            XCTAssertEqual(error as? OnlineSourcePolicy.PolicyError, .rejectedURL)
        }
    }

    func testHLSPlaylistParsesAES128KeyAndExplicitIV() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://hls.piotrt.cn/play/index.m3u8?auth_key=list"))
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-KEY:METHOD=AES-128,URI="https://ts.syjiaotong.mobi/play/crypt.key?auth_key=key%2Fvalue",IV=0x26cb7f063d34493f3746e85ef2c6bceb
        #EXTINF:4.0,
        https://ts.syjiaotong.mobi/play/segment-001.ts?auth_key=seg
        #EXT-X-ENDLIST
        """

        let parsed = try KnitHLSPlaylist.parse(playlist, baseURL: baseURL, source: .mrds)
        guard case let .media(segments) = parsed, let segment = segments.first else {
            return XCTFail("Expected a media playlist")
        }
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(
            segment.url.absoluteString,
            "https://ts.syjiaotong.mobi/play/segment-001.ts?auth_key=seg"
        )
        XCTAssertEqual(
            segment.encryption?.keyURL.absoluteString,
            "https://ts.syjiaotong.mobi/play/crypt.key?auth_key=key%2Fvalue"
        )
        XCTAssertEqual(segment.encryption?.iv.count, 16)
        XCTAssertEqual(
            segment.encryption?.iv,
            Data([0x26, 0xCB, 0x7F, 0x06, 0x3D, 0x34, 0x49, 0x3F, 0x37, 0x46, 0xE8, 0x5E, 0xF2, 0xC6, 0xBC, 0xEB])
        )
    }

    func testHLSPlaylistParsesMrdsRotatedSegmentHosts() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://hls.piotrt.cn/play/index.m3u8?auth_key=list"))
        let playlist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-KEY:METHOD=AES-128,URI="https://tx.doudou520.online/play/crypt.key?auth_key=key",IV=0x26cb7f063d34493f3746e85ef2c6bceb
        #EXTINF:4.0,
        https://tx.doudou520.online/play/segment-001.ts?auth_key=seg
        #EXT-X-KEY:METHOD=AES-128,URI="https://ts.zhixunkeji.xyz/play/crypt.key?auth_key=key2",IV=0x26cb7f063d34493f3746e85ef2c6bceb
        #EXTINF:4.0,
        https://ts.zhixunkeji.xyz/play/segment-002.ts?auth_key=seg2
        #EXT-X-ENDLIST
        """

        let parsed = try KnitHLSPlaylist.parse(playlist, baseURL: baseURL, source: .mrds)
        guard case let .media(segments) = parsed else {
            return XCTFail("Expected a media playlist")
        }
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(
            segments[0].url.absoluteString,
            "https://tx.doudou520.online/play/segment-001.ts?auth_key=seg"
        )
        XCTAssertEqual(
            segments[1].encryption?.keyURL.absoluteString,
            "https://ts.zhixunkeji.xyz/play/crypt.key?auth_key=key2"
        )
    }

    func testHLSPlaylistRejectedKeyHostIsPolicyError() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://hls.piotrt.cn/play/index.m3u8"))
        let playlist = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="https://cdn.evil.example/crypt.key",IV=0x26cb7f063d34493f3746e85ef2c6bceb
        #EXTINF:4.0,
        https://ts.syjiaotong.mobi/play/segment.ts
        #EXT-X-ENDLIST
        """
        XCTAssertThrowsError(try KnitHLSPlaylist.parse(playlist, baseURL: baseURL, source: .mrds)) { error in
            XCTAssertEqual(error as? OnlineSourcePolicy.PolicyError, .rejectedURL)
        }
    }

    func testHLSAES128RoundTripDecryptsPKCS7Payload() throws {
        let key = Data("1234567890abcdef".utf8)
        let iv = Data("abcdef9876543210".utf8)
        let plain = Data("mpeg-ts-payload-block!".utf8)
        let cipher = try KnitHLSAES128.encryptForTesting(plain, key: key, iv: iv)
        XCTAssertNotEqual(cipher, plain)
        XCTAssertEqual(try KnitHLSAES128.decrypt(cipher, key: key, iv: iv), plain)
    }

    func testVideoFilenameIsSanitizedAndUsesMP4Extension() throws {
        let item = try KnitGalleryItem(
            id: "32463",
            title: "Test / Video: 1V",
            rawTitle: "Test / Video: 1V",
            category: "Video",
            publishedDate: "",
            viewCount: nil,
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/32463/")),
            coverURL: nil,
            coverAspectRatio: 1,
            reportedPhotoCount: 1,
            reportedGIFCount: 0,
            reportedVideoCount: 1
        )

        XCTAssertEqual(
            KnitVideoDownloadService.suggestedFilename(for: item),
            "Test - Video- 1V-32463.mp4"
        )
    }

    func testVideoTransferMeterEstimatesTotalAndSmoothsSpeed() {
        let startedAt = Date(timeIntervalSince1970: 1000)
        var meter = KnitVideoTransferMeter(startedAt: startedAt)

        let first = meter.record(
            segmentBytes: 1000,
            completedSegments: 1,
            totalSegments: 4,
            at: startedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(first.downloadedBytes, 1000)
        XCTAssertEqual(first.estimatedTotalBytes, 4000)
        XCTAssertEqual(first.bytesPerSecond, 1000, accuracy: 0.001)
        XCTAssertEqual(first.averageBytesPerSecond, 1000, accuracy: 0.001)

        let second = meter.record(
            segmentBytes: 3000,
            completedSegments: 2,
            totalSegments: 4,
            at: startedAt.addingTimeInterval(2)
        )
        XCTAssertEqual(second.downloadedBytes, 4000)
        XCTAssertEqual(second.estimatedTotalBytes, 8000)
        XCTAssertEqual(second.bytesPerSecond, 1500, accuracy: 0.001)
        XCTAssertEqual(second.averageBytesPerSecond, 2000, accuracy: 0.001)
    }

    func testVideoProgressCarriesExactInstalledFileSize() {
        let progress = KnitVideoDownloadProgress(
            stage: .installingFile,
            completedSegments: 4,
            totalSegments: 4,
            downloadedBytes: 9876,
            totalBytes: 9876,
            averageBytesPerSecond: 1234
        )

        XCTAssertEqual(progress.fractionCompleted, 1)
        XCTAssertEqual(progress.downloadedBytes, 9876)
        XCTAssertEqual(progress.totalBytes, 9876)
        XCTAssertEqual(progress.bytesPerSecond, 0)
        XCTAssertEqual(progress.averageBytesPerSecond, 1234)
    }

    func testLiveKnitVideoCanBeSavedAsPlayableMP4WhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_KNIT_LIVE_VIDEO_TEST"] == "1" else {
            throw XCTSkip("Set RUN_KNIT_LIVE_VIDEO_TEST=1 to verify the current Knit HLS contract")
        }
        let sourceURL = try XCTUnwrap(URL(string: "https://media.knit.bid/play/239c2cd7dc95f643.m3u8"))
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHD-Knit-Live-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: targetURL) }

        try await KnitVideoDownloadService.saveMP4(from: sourceURL, to: targetURL) { _ in }

        let values = try targetURL.resourceValues(forKeys: [.fileSizeKey])
        XCTAssertGreaterThan(values.fileSize ?? 0, 1_000_000)
        let asset = AVURLAsset(url: targetURL)
        let isPlayable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertTrue(isPlayable)
        XCTAssertGreaterThan(duration.seconds, 1)
        XCTAssertFalse(videoTracks.isEmpty)
        XCTAssertFalse(audioTracks.isEmpty)
    }

    @MainActor
    func testFavoriteSourceUsesKnitDetailHost() {
        let record = FavoriteRecord(
            id: "knit:32463",
            sourceID: "wrong-source",
            title: "Test",
            rawTitle: "Test",
            subtitle: "",
            detailURL: "https://xx.knit.bid/article/32463/",
            coverURL: "https://xx.knit.bid/static/images/test.jpg",
            imageCount: 10,
            pageCount: 1
        )

        XCTAssertEqual(FavoriteSource.source(for: record), .knit)
        XCTAssertEqual(KnitFavoritesBridge.item(from: record)?.id, "32463")
    }

    @MainActor
    func testFilterSwitchRejectsStaleListResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KnitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KnitTests-\(UUID().uuidString)"))
        let favorites = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"), defaults: defaults)
        await favorites.waitUntilLoaded()
        let store = KnitGalleryStore(
            favorites: favorites,
            listResolver: { context, _ in
                switch context {
                case .filter(.all):
                    try await Task.sleep(for: .milliseconds(150))
                    return KnitListPage(items: [Self.item(id: "old")], currentPage: 1, totalPages: 1, nextPageURL: nil)
                case .filter(.popular):
                    try await Task.sleep(for: .milliseconds(10))
                    return KnitListPage(items: [Self.item(id: "new")], currentPage: 1, totalPages: 1, nextPageURL: nil)
                default:
                    return KnitListPage(items: [], currentPage: 1, totalPages: 1, nextPageURL: nil)
                }
            },
            detailResolver: { url in
                KnitResolvedDetailPage(pageURL: url, imageURLs: [], pageURLs: [url], videoURL: nil, metadata: nil)
            }
        )

        store.refreshFromNetwork()
        store.setFilter(.popular)
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(store.filter, .popular)
        XCTAssertEqual(store.items.map(\.id), ["new"])
    }

    @MainActor
    func testListPaginationPreservesCurrentDetailSession() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KnitTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KnitTests-\(UUID().uuidString)"))
        let favorites = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"), defaults: defaults)
        await favorites.waitUntilLoaded()
        var detailCalls = 0
        let first = Self.item(id: "old")
        let second = Self.item(id: "new")
        let imageURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/test.jpg"))
        let store = KnitGalleryStore(
            favorites: favorites,
            listResolver: { context, page in
                if page == 1 {
                    return KnitListPage(
                        items: [first], currentPage: 1, totalPages: 2,
                        nextPageURL: context.pageURL(page: 2)
                    )
                }
                return KnitListPage(items: [second], currentPage: 2, totalPages: 2, nextPageURL: nil)
            },
            detailResolver: { url in
                detailCalls += 1
                return KnitResolvedDetailPage(
                    pageURL: url, imageURLs: [imageURL], pageURLs: [url], videoURL: nil, metadata: nil
                )
            }
        )

        store.refreshFromNetwork()
        try await Self.waitUntil { store.selectedItemID == first.id }
        XCTAssertEqual(detailCalls, 0, "列表选择本身不应在详情区不可见时解析详情")
        store.resolveSelectedDetailIfNeeded()
        try await Self.waitUntil { store.selectedSlot?.knownURL == imageURL }
        store.loadMoreListIfNeeded()
        try await Self.waitUntil { store.currentPage == 2 }

        XCTAssertEqual(store.items.map(\.id), ["old", "new"])
        XCTAssertEqual(store.selectedItemID, "old")
        XCTAssertEqual(store.selectedSlot?.knownURL, imageURL)
        XCTAssertEqual(detailCalls, 1)
    }

    @MainActor
    func testLastImageStepsIntoRecommendationsAndBack() async throws {
        let fixture = try await Self.makeFavoritesFixture()
        defer { fixture.cleanup() }
        let first = Self.item(id: "old")
        let imageURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/old/01.jpg"))
        let recommendation = Self.recommendation(id: "recommended")
        let store = KnitGalleryStore(
            favorites: fixture.favorites,
            listResolver: { _, _ in
                KnitListPage(items: [first], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { url in
                KnitResolvedDetailPage(
                    pageURL: url,
                    imageURLs: [imageURL],
                    pageURLs: [url],
                    videoURL: nil,
                    metadata: nil,
                    recommendations: [recommendation]
                )
            }
        )

        store.refreshFromNetwork()
        try await Self.waitUntil { store.selectedItemID == first.id }
        store.resolveSelectedDetailIfNeeded()
        try await Self.waitUntil { store.isDetailResolutionComplete && store.recommendations.count == 1 }

        XCTAssertEqual(store.detailContentMode, .image)
        XCTAssertTrue(store.canStepDetailForward)
        store.stepImage(1)
        XCTAssertEqual(store.detailContentMode, .recommendations)
        XCTAssertTrue(store.canStepDetailBackward)

        store.stepImage(-1)
        XCTAssertEqual(store.detailContentMode, .image)
        XCTAssertEqual(store.selectedImageIndex, 0)
        XCTAssertEqual(store.selectedSlot?.knownURL, imageURL)
    }

    @MainActor
    func testCoverForwardWaitsForOriginalBeforeRecommendations() async throws {
        let fixture = try await Self.makeFavoritesFixture()
        defer { fixture.cleanup() }
        let detailURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/cover-only/"))
        let coverURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/cover-only/cover.jpg"))
        let originalURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/cover-only/01.jpg"))
        let recommendation = Self.recommendation(id: "after-cover")
        let item = KnitGalleryItem(
            id: "cover-only",
            title: "cover-only",
            rawTitle: "cover-only",
            category: "Test",
            publishedDate: "",
            viewCount: nil,
            detailURL: detailURL,
            coverURL: coverURL,
            coverAspectRatio: 0.75,
            reportedPhotoCount: 1,
            reportedGIFCount: 0,
            reportedVideoCount: 0
        )
        let detailStarted = expectation(description: "cover detail starts")
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let store = KnitGalleryStore(
            favorites: fixture.favorites,
            listResolver: { _, _ in
                KnitListPage(items: [item], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { url in
                detailStarted.fulfill()
                for await _ in gate.stream {
                    break
                }
                return KnitResolvedDetailPage(
                    pageURL: url,
                    imageURLs: [originalURL],
                    pageURLs: [url],
                    videoURL: nil,
                    metadata: nil,
                    recommendations: [recommendation]
                )
            }
        )

        store.refreshFromNetwork()
        try await Self.waitUntil { store.selectedSlot?.knownURL == coverURL }
        XCTAssertFalse(store.hasResolvedSelectedImage)
        store.resolveSelectedDetailIfNeeded()
        await fulfillment(of: [detailStarted], timeout: 1.0)

        store.stepImage(1)
        XCTAssertEqual(store.detailContentMode, .image)
        XCTAssertEqual(store.selectedSlot?.knownURL, coverURL)

        gate.continuation.yield()
        gate.continuation.finish()
        try await Self.waitUntil {
            store.isDetailResolutionComplete && store.selectedSlot?.knownURL == originalURL
        }
        XCTAssertEqual(store.detailContentMode, .image)
        XCTAssertTrue(store.hasResolvedSelectedImage)

        store.stepImage(1)
        XCTAssertEqual(store.detailContentMode, .recommendations)
    }

    @MainActor
    func testInFlightDetailPageDoesNotEnterRecommendationsEarly() async throws {
        let fixture = try await Self.makeFavoritesFixture()
        defer { fixture.cleanup() }
        let first = Self.item(id: "old")
        let page1 = first.detailURL
        let page2 = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/1/page/2/"))
        let image1 = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/old/01.jpg"))
        let image2 = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/old/02.jpg"))
        let recommendation = Self.recommendation(id: "recommended")
        let page2Started = expectation(description: "second detail page starts")
        let gate = AsyncStream<Void>.makeStream()
        let store = KnitGalleryStore(
            favorites: fixture.favorites,
            listResolver: { _, _ in
                KnitListPage(items: [first], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { url in
                if url == page2 {
                    page2Started.fulfill()
                    for await _ in gate.stream {
                        break
                    }
                    return KnitResolvedDetailPage(
                        pageURL: page2,
                        imageURLs: [image2],
                        pageURLs: [page1, page2],
                        videoURL: nil,
                        metadata: nil
                    )
                }
                return KnitResolvedDetailPage(
                    pageURL: page1,
                    imageURLs: [image1],
                    pageURLs: [page1, page2],
                    videoURL: nil,
                    metadata: nil,
                    recommendations: [recommendation]
                )
            }
        )

        store.refreshFromNetwork()
        try await Self.waitUntil { store.selectedItemID == first.id }
        store.resolveSelectedDetailIfNeeded()
        await fulfillment(of: [page2Started], timeout: 1.0)
        try await Self.waitUntil { store.selectedSlot?.knownURL == image1 }

        store.stepImage(1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(store.detailContentMode, .image)
        XCTAssertEqual(store.selectedSlot?.knownURL, image1)
        XCTAssertFalse(store.isDetailResolutionComplete)

        gate.continuation.yield()
        gate.continuation.finish()
        try await Self.waitUntil { store.selectedSlot?.knownURL == image2 }
        XCTAssertEqual(store.detailContentMode, .image)

        store.stepImage(1)
        XCTAssertEqual(store.detailContentMode, .recommendations)
    }

    @MainActor
    func testInitialPrefetchWaitsForContinuousPagePrefix() async throws {
        let fixture = try await Self.makeFavoritesFixture()
        defer { fixture.cleanup() }
        let item = Self.item(id: "old")
        let remainingPageURLs = try (2 ... 5).map { page in
            try XCTUnwrap(URL(string: "https://xx.knit.bid/article/1/page/\(page)/"))
        }
        let pageURLs = [item.detailURL] + remainingPageURLs
        let page2Started = expectation(description: "page 2 starts")
        let page3Started = expectation(description: "page 3 starts")
        let page2Gate = AsyncStream<Void>.makeStream()
        let page3Gate = AsyncStream<Void>.makeStream()
        let page4Gate = AsyncStream<Void>.makeStream()
        defer {
            page2Gate.continuation.finish()
            page3Gate.continuation.finish()
            page4Gate.continuation.finish()
        }
        var activeRequests = 0
        var maximumActiveRequests = 0
        var requestedPages: [URL] = []
        let store = KnitGalleryStore(
            favorites: fixture.favorites,
            listResolver: { _, _ in
                KnitListPage(items: [item], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { url in
                if url == item.detailURL {
                    return KnitResolvedDetailPage(
                        pageURL: url,
                        imageURLs: [URL(string: "https://xx.knit.bid/static/images/old/01.jpg")!],
                        pageURLs: pageURLs,
                        videoURL: nil,
                        metadata: nil
                    )
                }

                activeRequests += 1
                maximumActiveRequests = max(maximumActiveRequests, activeRequests)
                requestedPages.append(url)
                defer { activeRequests -= 1 }
                if url == pageURLs[1] {
                    page2Started.fulfill()
                    for await _ in page2Gate.stream {
                        break
                    }
                } else if url == pageURLs[2] {
                    page3Started.fulfill()
                    for await _ in page3Gate.stream {
                        break
                    }
                } else {
                    for await _ in page4Gate.stream {
                        break
                    }
                }
                return KnitResolvedDetailPage(
                    pageURL: url,
                    imageURLs: [URL(string: "https://xx.knit.bid/static/images/old/\(requestedPages.count + 1).jpg")!],
                    pageURLs: pageURLs,
                    videoURL: nil,
                    metadata: nil
                )
            }
        )

        store.refreshFromNetwork()
        try await Self.waitUntil { store.selectedItemID == item.id }
        store.resolveSelectedDetailIfNeeded()
        await fulfillment(of: [page2Started], timeout: 1.0)

        for _ in 0 ..< 8 {
            store.ensureNextDetailPageLoaded()
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(requestedPages, [pageURLs[1]])
        XCTAssertEqual(maximumActiveRequests, 1)

        page2Gate.continuation.yield()
        page2Gate.continuation.finish()
        await fulfillment(of: [page3Started], timeout: 1.0)
        XCTAssertEqual(requestedPages, [pageURLs[1], pageURLs[2]])

        for _ in 0 ..< 8 {
            store.ensureNextDetailPageLoaded()
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(requestedPages, [pageURLs[1], pageURLs[2]])
        XCTAssertEqual(maximumActiveRequests, 1)

        page3Gate.continuation.yield()
        page3Gate.continuation.finish()
        try await Self.waitUntil { requestedPages.count == 3 }
        XCTAssertEqual(requestedPages, [pageURLs[1], pageURLs[2], pageURLs[3]])
        XCTAssertEqual(maximumActiveRequests, 1)
    }

    @MainActor
    func testOffFeedRecommendationSelectionSurvivesListPagination() async throws {
        let fixture = try await Self.makeFavoritesFixture()
        defer { fixture.cleanup() }
        let first = Self.item(id: "old")
        let second = Self.item(id: "new")
        let recommendation = Self.recommendation(id: "recommended")
        let store = KnitGalleryStore(
            favorites: fixture.favorites,
            listResolver: { context, page in
                if page == 1 {
                    return KnitListPage(
                        items: [first],
                        currentPage: 1,
                        totalPages: 2,
                        nextPageURL: context.pageURL(page: 2)
                    )
                }
                return KnitListPage(items: [second], currentPage: 2, totalPages: 2, nextPageURL: nil)
            },
            detailResolver: { url in
                KnitResolvedDetailPage(
                    pageURL: url,
                    imageURLs: [URL(string: "https://xx.knit.bid/static/images/\(url.lastPathComponent)/01.jpg")!],
                    pageURLs: [url],
                    videoURL: nil,
                    metadata: nil,
                    recommendations: url == first.detailURL ? [recommendation] : []
                )
            }
        )

        store.refreshFromNetwork()
        try await Self.waitUntil { store.selectedItemID == first.id }
        store.resolveSelectedDetailIfNeeded()
        try await Self.waitUntil { store.recommendations.count == 1 && store.isDetailResolutionComplete }
        store.openRecommendation(recommendation)
        try await Self.waitUntil { store.selectedItem?.detailURL == recommendation.detailURL }

        XCTAssertEqual(store.selectedItemID, "recommended")
        XCTAssertEqual(store.selectedItem?.title, recommendation.title)
        XCTAssertFalse(store.items.contains { $0.id == "recommended" })

        store.loadMoreListIfNeeded()
        try await Self.waitUntil { store.currentPage == 2 }

        XCTAssertEqual(store.items.map(\.id), ["old", "new"])
        XCTAssertEqual(store.selectedItemID, "recommended")
        XCTAssertEqual(store.selectedItem?.detailURL, recommendation.detailURL)
        XCTAssertFalse(store.items.contains { $0.id == "recommended" })
    }

    @MainActor
    func testOffFeedRecommendationOpenedDuringInitialFeedRequestSurvivesReplacement() async throws {
        let fixture = try await Self.makeFavoritesFixture()
        defer { fixture.cleanup() }
        let feedItem = Self.item(id: "old")
        let recommendation = Self.recommendation(id: "900")
        let recommendationImage = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/900/01.jpg"))
        let listStarted = expectation(description: "initial feed request starts")
        let listGate = AsyncStream<Void>.makeStream()
        defer { listGate.continuation.finish() }
        let store = KnitGalleryStore(
            favorites: fixture.favorites,
            listResolver: { _, _ in
                listStarted.fulfill()
                for await _ in listGate.stream {
                    break
                }
                return KnitListPage(items: [feedItem], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { url in
                KnitResolvedDetailPage(
                    pageURL: url,
                    imageURLs: [recommendationImage],
                    pageURLs: [url],
                    videoURL: nil,
                    metadata: nil
                )
            }
        )

        store.refreshFromNetwork()
        await fulfillment(of: [listStarted], timeout: 1.0)
        store.openRecommendation(recommendation)
        store.resolveSelectedDetailIfNeeded()
        try await Self.waitUntil {
            store.selectedItem?.detailURL == recommendation.detailURL
                && store.selectedSlot?.knownURL == recommendationImage
                && store.isDetailResolutionComplete
        }

        listGate.continuation.yield()
        listGate.continuation.finish()
        try await Self.waitUntil { store.currentPage == 1 && !store.isRefreshingList }

        XCTAssertEqual(store.items.map(\.id), ["old"])
        XCTAssertEqual(store.selectedItemID, "900")
        XCTAssertEqual(store.selectedItem?.detailURL, recommendation.detailURL)
        XCTAssertEqual(store.selectedSlot?.knownURL, recommendationImage)
        XCTAssertTrue(store.isDetailResolutionComplete)
    }

    @MainActor
    func testFailedMiddleDetailPageBlocksRecommendationsUntilExplicitRetryRestoresPrefix() async throws {
        let fixture = try await Self.makeFavoritesFixture()
        defer { fixture.cleanup() }
        let first = Self.item(id: "old")
        let page1 = first.detailURL
        let page2 = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/1/page/2/"))
        let page3 = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/1/page/3/"))
        let image1 = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/old/01.jpg"))
        let image2 = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/old/02.jpg"))
        let image3 = try XCTUnwrap(URL(string: "https://xx.knit.bid/static/images/old/03.jpg"))
        let recommendation = Self.recommendation(id: "901")
        var page2Attempts = 0
        var page3Calls = 0
        let store = KnitGalleryStore(
            favorites: fixture.favorites,
            listResolver: { _, _ in
                KnitListPage(items: [first], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { url in
                switch url {
                case page2:
                    page2Attempts += 1
                    if page2Attempts == 1 {
                        throw URLError(.badServerResponse)
                    }
                    return KnitResolvedDetailPage(
                        pageURL: page2,
                        imageURLs: [image2],
                        pageURLs: [page1, page2, page3],
                        videoURL: nil,
                        metadata: nil
                    )
                case page3:
                    page3Calls += 1
                    return KnitResolvedDetailPage(
                        pageURL: page3,
                        imageURLs: [image3],
                        pageURLs: [page1, page2, page3],
                        videoURL: nil,
                        metadata: nil
                    )
                default:
                    return KnitResolvedDetailPage(
                        pageURL: page1,
                        imageURLs: [image1],
                        pageURLs: [page1, page2, page3],
                        videoURL: nil,
                        metadata: nil,
                        recommendations: [recommendation]
                    )
                }
            }
        )

        store.refreshFromNetwork()
        try await Self.waitUntil { store.selectedItemID == first.id }
        store.resolveSelectedDetailIfNeeded()
        try await Self.waitUntil { store.detailErrorMessage != nil }

        XCTAssertEqual(store.imageSlots.map(\.knownURL), [image1])
        XCTAssertEqual(page2Attempts, 1)
        XCTAssertEqual(page3Calls, 0)
        XCTAssertFalse(store.isDetailResolutionComplete)

        store.stepImage(1)
        XCTAssertEqual(store.detailContentMode, .image)
        XCTAssertEqual(store.selectedSlot?.knownURL, image1)
        for _ in 0 ..< 4 {
            store.ensureNextDetailPageLoaded()
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(page2Attempts, 1)
        XCTAssertEqual(page3Calls, 0)
        XCTAssertFalse(store.isDetailResolutionComplete)

        // 详情区状态条的点击动作调用 retryLastFailure()。
        store.retryLastFailure()
        try await Self.waitUntil {
            store.isDetailResolutionComplete && store.imageSlots.count == 3
        }

        XCTAssertEqual(page2Attempts, 2)
        XCTAssertEqual(page3Calls, 1)
        XCTAssertEqual(store.imageSlots.map(\.knownURL), [image1, image2, image3])
        XCTAssertEqual(store.selectedImageIndex, 1)
        XCTAssertEqual(store.detailContentMode, .image)
        XCTAssertNil(store.detailErrorMessage)

        store.stepImage(1)
        XCTAssertEqual(store.selectedSlot?.knownURL, image3)
        XCTAssertEqual(store.detailContentMode, .image)
        store.stepImage(1)
        XCTAssertEqual(store.detailContentMode, .recommendations)
    }

    private static func item(id: String) -> KnitGalleryItem {
        KnitGalleryItem(
            id: id,
            title: id,
            rawTitle: id,
            category: "Test",
            publishedDate: "",
            viewCount: nil,
            detailURL: URL(string: "https://xx.knit.bid/article/\(id == "old" ? 1 : 2)/")!,
            coverURL: nil,
            coverAspectRatio: 1.5,
            reportedPhotoCount: 1,
            reportedGIFCount: 0,
            reportedVideoCount: 0
        )
    }

    private static func recommendation(id: String) -> OnlineGalleryRecommendation {
        OnlineGalleryRecommendation(
            title: "Recommendation \(id)",
            detailURL: URL(string: "https://xx.knit.bid/article/\(id)/")!,
            coverURL: URL(string: "https://xx.knit.bid/static/images/\(id)/cover.jpg"),
            coverAspectRatio: 0.75,
            imageCount: 1
        )
    }

    private static func cardHTML(id: String, title: String) -> String {
        #"""
        <article class="excerpt excerpt-c4">
          <a href="/type/3/" class="imgbox-a" title="丝袜美女">丝袜美女</a>
          <a class="imgbox imgbox-link" href="/article/\#(id)/" title="\#(title)">
            <img class="imgbox-img" src="/static/zde/timg.gif"
                 data-original-src="/static/images/\#(id)/cover.jpg">
          </a>
          <h2><a>\#(title)</a></h2>
        </article>
        """#
    }

    @MainActor
    private static func makeFavoritesFixture() async throws -> FavoritesFixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("KnitTests-\(UUID().uuidString)")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "KnitTests-\(UUID().uuidString)"))
        let favorites = FavoritesStore(fileURL: root.appendingPathComponent("favorites.json"), defaults: defaults)
        await favorites.waitUntilLoaded()
        return FavoritesFixture(root: root, favorites: favorites)
    }

    @MainActor
    private static func waitUntil(
        attempts: Int = 150,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0 ..< attempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous Knit state")
    }

    private struct FavoritesFixture {
        let root: URL
        let favorites: FavoritesStore

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
