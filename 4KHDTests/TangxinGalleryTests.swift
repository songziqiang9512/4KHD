@testable import _KHD
import XCTest

final class TangxinGalleryTests: XCTestCase {
    func testSidebarSectionsKeepFixedOrder() {
        XCTAssertEqual(TangxinSection.allCases.map(\.rawValue), ["latest", "tags", "authors"])
        XCTAssertEqual(TangxinSection.latest.title, "最近更新")
        XCTAssertEqual(TangxinSection.tags.title, "分类")
        XCTAssertEqual(TangxinSection.authors.title, "作者")
        XCTAssertEqual(
            TangxinRoute.latest.listURL(searchQuery: nil)?.absoluteString,
            "https://tangxinvlog.app/featured/"
        )
        XCTAssertEqual(
            TangxinRoute.latest.listURL(searchQuery: "hello")?.absoluteString,
            "https://tangxinvlog.app/rss.xml?q=hello"
        )
    }

    func testRouteParseRecognizesDeepLinks() {
        XCTAssertEqual(TangxinRoute.parse("latest"), .latest)
        XCTAssertEqual(TangxinRoute.parse("tags")?.itemID, "tags")
        XCTAssertEqual(TangxinRoute.parse("tag:silk"), .tag("silk"))
        XCTAssertEqual(TangxinRoute.parse("author:岛国梦工厂"), .author("岛国梦工厂"))
        XCTAssertEqual(TangxinRoute.parse("related:36005"), .related("36005"))
        XCTAssertNil(TangxinRoute.parse("related:abc"))
        XCTAssertNil(TangxinRoute.parse("unknown"))
        XCTAssertEqual(TangxinRoute.parse("tag:silk")?.sidebarSection, .tags)
        XCTAssertEqual(TangxinRoute.parse("author:a")?.sidebarSection, .authors)
        XCTAssertEqual(TangxinRoute.parse("related:1")?.sidebarSection, .latest)
        XCTAssertEqual(
            TangxinRoute.tag("silk").listURL(searchQuery: nil)?.absoluteString,
            "https://tangxinvlog.app/tag/silk/"
        )
        XCTAssertEqual(
            TangxinRoute.related("36005").listURL(searchQuery: nil)?.absoluteString,
            "https://tangxinvlog.app/v/36005/"
        )
    }

    func testListParserKeepsVideoCardsAndSkipsAds() throws {
        let html = """
        <article class="card">
          <a class="cover-link" href="/v/36005/" aria-label="公开条目">
            <img src="https://t.5gcdn.xyz/videos/36005/cover.jpg" width="640" height="360">
            <span class="duration">12:34</span>
          </a>
          <a class="nickname" href="/a/%E5%B2%9B%E5%9B%BD%E6%A2%A6%E5%B7%A5%E5%8E%82/">岛国梦工厂</a>
        </article>
        <article class="card">
          <a class="cover-link" href="https://afengyue.com/ad" aria-label="广告">
            <img src="https://afengyue.com/fengyue.gif">
          </a>
        </article>
        <link rel="next" href="https://tangxinvlog.app/featured/2">
        <span class="pager-status">1 / 143</span>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://tangxinvlog.app/featured/"))
        let page = try TangxinListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.map(\.id), ["36005"])
        XCTAssertEqual(page.items.first?.title, "公开条目")
        XCTAssertEqual(page.items.first?.durationText, "12:34")
        XCTAssertEqual(page.items.first?.authorName, "岛国梦工厂")
        XCTAssertEqual(page.items.first?.authorFilter, "author:岛国梦工厂")
        XCTAssertEqual(page.items.first?.gridCardMetadata(isFavorite: false), "岛国梦工厂 · 12:34")
        XCTAssertEqual(
            page.items.first?.gridCardMetadata(isFavorite: true),
            "岛国梦工厂 · 12:34 · 已收藏"
        )
        XCTAssertEqual(page.items.first?.listSecondaryLine, "岛国梦工厂 · 12:34")
        XCTAssertNil(page.items.first?.opensFilter)
        XCTAssertEqual(
            page.items.first?.coverURL?.absoluteString,
            "https://t.5gcdn.xyz/videos/36005/cover.jpg"
        )
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.totalPages, 143)
        XCTAssertEqual(page.nextPageURL?.absoluteString, "https://tangxinvlog.app/featured/2")
    }

    func testTagAndAuthorDirectoryItemsOpenFilterInsteadOfPlaying() throws {
        let tagHTML = """
        <ul class="tag-cloud">
          <li><a href="/tag/silk/"><span class="name">丝袜</span><span class="num">12</span></a></li>
          <li><a href="/zh-tw/tag/silk/"><span class="name">繁中</span><span class="num">1</span></a></li>
        </ul>
        """
        let tagURL = try XCTUnwrap(URL(string: "https://tangxinvlog.app/tag/"))
        let tags = try TangxinListResolver.parse(data: Data(tagHTML.utf8), pageURL: tagURL)
        XCTAssertEqual(tags.items.map(\.id), ["tag:silk"])
        XCTAssertEqual(tags.items.first?.opensFilter, "tag:silk")
        XCTAssertEqual(tags.items.first?.title, "丝袜")
        XCTAssertEqual(tags.items.first?.subtitle, "12 部")
        XCTAssertTrue(tags.items.first?.isDirectoryEntry == true)
        XCTAssertEqual(tags.nextPageURL, nil)

        let authorHTML = """
        <ul class="artist-cloud">
          <li><a href="/a/Sweetie%20Fox(%E5%B0%8F%E7%8B%90%E7%8B%B8)/"><span class="name">Sweetie Fox(小狐狸)</span><span class="num">3</span></a></li>
        </ul>
        """
        let authorURL = try XCTUnwrap(URL(string: "https://tangxinvlog.app/a/"))
        let authors = try TangxinListResolver.parse(data: Data(authorHTML.utf8), pageURL: authorURL)
        XCTAssertEqual(authors.items.count, 1)
        XCTAssertEqual(authors.items.first?.opensFilter, "author:Sweetie Fox(小狐狸)")
        XCTAssertEqual(authors.items.first?.subtitle, "3 部")
        XCTAssertTrue(authors.items.first?.isDirectoryEntry == true)
        XCTAssertEqual(
            authors.items.first?.detailURL.absoluteString,
            "https://tangxinvlog.app/a/Sweetie%20Fox(%E5%B0%8F%E7%8B%90%E7%8B%B8)/"
        )
    }

    func testWatchPageListKeepsRelatedCardsAndIgnoresCurrentPlaylist() throws {
        let html = """
        <video id="player" poster="https://t.5gcdn.xyz/videos/36005/cover.jpg"></video>
        <script>const m3u8 = "https://t.5gcdn.xyz/videos/36005/index.m3u8";</script>
        <div class="related-grid">
          <article class="card">
            <a class="cover-link" href="/v/36006/" aria-label="相关条目">
              <img src="https://t.5gcdn.xyz/videos/36006/cover.jpg">
            </a>
          </article>
        </div>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://tangxinvlog.app/v/36005/"))
        let page = try TangxinListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.map(\.id), ["36006"])
        XCTAssertFalse(page.items.contains(where: { $0.id == "36005" }))
    }

    func testDetailParserRequiresCurrentVideoIDAndRejectsRelatedPlaylist() throws {
        let html = """
        <script>const leftover = "https://t.5gcdn.xyz/videos/99999/index.m3u8";</script>
        <script>const m3u8 = "https://t.5gcdn.xyz/videos/36005/index.m3u8";</script>
        <script type="application/ld+json">{"contentUrl":"https://t.5gcdn.xyz/videos/99999/index.m3u8"}</script>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://tangxinvlog.app/v/36005/"))
        let detail = try TangxinDetailResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(detail.videoURL.absoluteString, "https://t.5gcdn.xyz/videos/36005/index.m3u8")
        XCTAssertEqual(
            detail.coverURL?.absoluteString,
            "https://t.5gcdn.xyz/videos/36005/cover.jpg"
        )

        XCTAssertThrowsError(
            try TangxinDetailResolver.parse(
                data: Data("<html>no playlist</html>".utf8),
                pageURL: pageURL
            )
        ) { error in
            XCTAssertEqual(error as? TangxinDetailResolverError, .missingPlaylist)
        }

        let relatedOnly = """
        <script>const m3u8 = "https://t.5gcdn.xyz/videos/99999/index.m3u8";</script>
        """
        XCTAssertThrowsError(
            try TangxinDetailResolver.parse(data: Data(relatedOnly.utf8), pageURL: pageURL)
        ) { error in
            XCTAssertEqual(error as? TangxinDetailResolverError, .missingPlaylist)
        }
    }

    func testPagerNextLinkFromAnchor() throws {
        let html = """
        <article class="card">
          <a class="cover-link" href="/v/1/" aria-label="条目"><img src="https://t.5gcdn.xyz/videos/1/cover.jpg"></a>
        </article>
        <a class="pager-link" href="/tag/silk/2">下一页 →</a>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://tangxinvlog.app/tag/silk/"))
        let page = try TangxinListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.nextPageURL?.absoluteString, "https://tangxinvlog.app/tag/silk/2")
    }

    func testRSSSearchFiltersByTitleAndCapsResults() throws {
        var items = ""
        for index in 1 ... 205 {
            items += """
            <item>
              <title>条目\(index) 公开测试</title>
              <link>https://tangxinvlog.app/v/\(index)/</link>
              <description>标签</description>
            </item>
            """
        }
        items += """
        <item>
          <title>无关标题</title>
          <link>https://tangxinvlog.app/v/99999/</link>
        </item>
        """
        let rss = "<rss><channel>\(items)</channel></rss>"
        let pageURL = try XCTUnwrap(URL(string: "https://tangxinvlog.app/rss.xml?q=公开测试"))
        let page = try TangxinListResolver.parse(data: Data(rss.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.count, TangxinListResolver.searchResultLimit)
        XCTAssertEqual(page.items.first?.id, "1")
        XCTAssertEqual(page.items.last?.id, "200")
        XCTAssertFalse(page.items.contains(where: { $0.id == "99999" }))
        XCTAssertNil(page.nextPageURL)
        XCTAssertEqual(
            page.items.first?.coverURL?.absoluteString,
            "https://t.5gcdn.xyz/videos/1/cover.jpg"
        )
    }

    func testPolicyRejectsLookalikeHosts() throws {
        let html = try XCTUnwrap(URL(string: "https://tangxinvlog.app/v/36005/"))
        let rss = try XCTUnwrap(URL(string: "https://tangxinvlog.app/rss.xml"))
        let lookalike = try XCTUnwrap(URL(string: "https://tangxinvlog.app.evil.example/v/36005/"))
        let cover = try XCTUnwrap(URL(string: "https://t.5gcdn.xyz/videos/36005/cover.jpg"))
        let playlist = try XCTUnwrap(URL(string: "https://t.5gcdn.xyz/videos/36005/index.m3u8"))
        let mediaLookalike = try XCTUnwrap(URL(string: "https://t.5gcdn.xyz.evil.example/videos/36005/index.m3u8"))
        let ad = try XCTUnwrap(URL(string: "https://afengyue.com/fengyue.gif"))

        XCTAssertTrue(OnlineSourcePolicy.allows(html, source: .tangxin, resource: .html))
        XCTAssertTrue(OnlineSourcePolicy.allows(rss, source: .tangxin, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(lookalike, source: .tangxin, resource: .html))
        XCTAssertTrue(OnlineSourcePolicy.allows(cover, source: .tangxin, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(playlist, source: .tangxin, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(mediaLookalike, source: .tangxin, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(ad, source: .tangxin, resource: .media))
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: cover), .tangxin)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: playlist), .tangxin)
    }

    func testFavoritesBridgeRequiresWatchPath() throws {
        let item = try OnlineVideoItem(
            id: "36005",
            title: "Demo",
            subtitle: "糖心Vlog",
            detailURL: XCTUnwrap(URL(string: "https://tangxinvlog.app/v/36005/")),
            coverURL: XCTUnwrap(URL(string: "https://t.5gcdn.xyz/videos/36005/cover.jpg")),
            coverAspectRatio: 16.0 / 9.0,
            durationText: "12:34"
        )
        let record = TangxinFavoritesBridge.record(from: item)
        XCTAssertEqual(FavoriteSource.source(for: record), .tangxin)
        XCTAssertEqual(TangxinFavoritesBridge.item(from: record)?.id, "36005")
        XCTAssertNil(TangxinFavoritesBridge.item(from: FavoriteRecord(
            id: "tangxin:x", sourceID: "tangxin", title: "x", rawTitle: "x", subtitle: "",
            detailURL: "https://tangxinvlog.app/tag/silk/", coverURL: nil, imageCount: 0, pageCount: 1
        )))
        XCTAssertNil(try TangxinFavoritesBridge.videoID(from: XCTUnwrap(URL(string: "https://tangxinvlog.app/a/name/"))))
    }

    func testLocalProxyMapsHTTPSMediaOntoLoopbackAndRewritesAbsoluteURIs() throws {
        let media = try XCTUnwrap(URL(string: "https://t.5gcdn.xyz/videos/36005/index.m3u8"))
        let sessionID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let local = try XCTUnwrap(
            OnlineHLSLocalProxy.localMediaURL(from: media, sessionID: sessionID, port: 18400)
        )
        XCTAssertEqual(local.scheme, "http")
        XCTAssertEqual(local.host, "127.0.0.1")
        XCTAssertEqual(local.port, 18400)
        XCTAssertTrue(local.path.contains("/khd/\(sessionID.uuidString)/t.5gcdn.xyz/videos/36005/index.m3u8"))
        let parsed = try XCTUnwrap(OnlineHLSLocalProxy.remoteMediaURL(from: local))
        XCTAssertEqual(parsed.sessionID, sessionID)
        XCTAssertEqual(parsed.mediaURL.absoluteString, media.absoluteString)

        let playlist = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="enc.key"
        #EXTINF:4.0,
        seg0.ts
        https://t.5gcdn.xyz/videos/36005/seg1.ts
        https://evil.example/seg2.ts
        """
        let rewritten = OnlineHLSLocalProxy.rewriteAbsoluteMediaURIs(
            in: playlist,
            playlistURL: media,
            sessionID: sessionID,
            port: 18400,
            source: .tangxin
        )
        XCTAssertFalse(rewritten.contains("#EXT-X-KEY"))
        XCTAssertFalse(rewritten.contains("enc.key"))
        XCTAssertTrue(rewritten.contains("\nseg0.ts"))
        XCTAssertTrue(
            rewritten.contains(
                "http://127.0.0.1:18400/khd/\(sessionID.uuidString)/t.5gcdn.xyz/videos/36005/seg1.ts"
            )
        )
        XCTAssertTrue(rewritten.contains("https://evil.example/seg2.ts"))

        let aes = KnitHLSPlaylist.playbackAES128(playlist, baseURL: media, source: .tangxin)
        XCTAssertEqual(aes?.keyURL.absoluteString, "https://t.5gcdn.xyz/videos/36005/enc.key")
        XCTAssertEqual(aes?.defaultIV.count, 16)
        XCTAssertEqual(OnlineHLSLocalProxy.playlistContentType, "application/vnd.apple.mpegurl")
        XCTAssertEqual(
            OnlineSourcePolicy.originHeader(fromReferer: "https://tangxinvlog.app/"),
            "https://tangxinvlog.app"
        )
    }

    @MainActor
    func testSwitchingToDirectoryClearsStaleVideosAndReusesCache() async throws {
        let video = try makeStoreVideoItem(id: "36005", title: "公开条目")
        let tag = try makeStoreDirectoryItem(id: "tag:silk", title: "丝袜", filter: "tag:silk")
        var tagResolveCount = 0
        let store = OnlineVideoGalleryStore(
            policySource: .tangxin,
            sourceTitle: "糖心Vlog",
            defaultFilter: "latest",
            favorites: FavoritesStore(),
            listURL: { filter, _ in
                filter == "tags"
                    ? URL(string: "https://tangxinvlog.app/tag/")
                    : URL(string: "https://tangxinvlog.app/featured/")
            },
            filterTitle: { $0 },
            listResolver: { url in
                if url.path == "/tag/" || url.path == "/tag" {
                    tagResolveCount += 1
                    return OnlineVideoListPage(items: [tag], currentPage: 1, totalPages: 1, nextPageURL: nil)
                }
                return OnlineVideoListPage(items: [video], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { _ in
                throw OnlineVideoPlaybackError.notAVideo
            },
            makeFavoriteRecord: TangxinFavoritesBridge.record(from:),
            directoryFilters: ["tags"]
        )

        store.bootstrapIfNeeded()
        await waitUntil { store.items.map(\.id) == ["36005"] }
        store.setFilter("tags")
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.showsDirectoryListing)
        await waitUntil { store.items.map(\.id) == ["tag:silk"] }
        XCTAssertEqual(tagResolveCount, 1)
        XCTAssertEqual(store.displayFilterTitle, "tags")

        store.setFilter("tag:silk")
        XCTAssertEqual(store.displayFilterTitle, "丝袜")

        store.setFilter("latest")
        XCTAssertEqual(store.items.map(\.id), ["36005"])
        store.setFilter("tags")
        XCTAssertEqual(store.items.map(\.id), ["tag:silk"])
        XCTAssertEqual(tagResolveCount, 1)
    }

    @MainActor
    func testDirectorySearchFiltersChipsLocally() async throws {
        let silk = try makeStoreDirectoryItem(id: "tag:silk", title: "丝袜", filter: "tag:silk")
        let other = try makeStoreDirectoryItem(id: "tag:other", title: "其他", filter: "tag:other")
        let store = OnlineVideoGalleryStore(
            policySource: .tangxin,
            sourceTitle: "糖心Vlog",
            defaultFilter: "tags",
            favorites: FavoritesStore(),
            listURL: { _, _ in URL(string: "https://tangxinvlog.app/tag/") },
            filterTitle: { $0 },
            listResolver: { _ in
                OnlineVideoListPage(items: [silk, other], currentPage: 1, totalPages: 1, nextPageURL: nil)
            },
            detailResolver: { _ in
                throw OnlineVideoPlaybackError.notAVideo
            },
            makeFavoriteRecord: TangxinFavoritesBridge.record(from:)
        )

        store.bootstrapIfNeeded()
        await waitUntil { store.items.count == 2 }
        store.searchText = "丝"
        store.submitSearch()
        XCTAssertEqual(store.items.map(\.id), ["tag:silk"])
        XCTAssertEqual(store.activeSearchQuery, "丝")
        store.clearSearch()
        XCTAssertEqual(store.items.map(\.id), ["tag:silk", "tag:other"])
        XCTAssertNil(store.activeSearchQuery)
    }

    @MainActor
    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for store state")
    }

    private func makeStoreVideoItem(id: String, title: String) throws -> OnlineVideoItem {
        try OnlineVideoItem(
            id: id,
            title: title,
            subtitle: "糖心Vlog",
            detailURL: XCTUnwrap(URL(string: "https://tangxinvlog.app/v/\(id)/")),
            coverURL: nil,
            coverAspectRatio: 16.0 / 9.0,
            durationText: "12:34"
        )
    }

    private func makeStoreDirectoryItem(id: String, title: String, filter: String) throws -> OnlineVideoItem {
        try OnlineVideoItem(
            id: id,
            title: title,
            subtitle: "12 部",
            detailURL: XCTUnwrap(URL(string: "https://tangxinvlog.app/tag/silk/")),
            coverURL: nil,
            coverAspectRatio: 16.0 / 9.0,
            durationText: "",
            opensFilter: filter
        )
    }
}
