@testable import _KHD
import AppKit
import XCTest

final class MrdsGalleryTests: XCTestCase {
    func testSidebarSectionsKeepSiteNavOrder() {
        XCTAssertEqual(
            MrdsSection.allCases.map(\.rawValue),
            [
                "latest", "mrds", "ztds", "rstt", "xazd", "blyp", "fctg", "mhds",
                "lqdp", "jdsj", "mxwh", "smdh", "dypd", "mtds", "ysds", "czds",
                "hjds", "tgds", "omjp", "qwcs", "aijc",
            ]
        )
        XCTAssertEqual(MrdsSection.latest.title, "最近更新")
        XCTAssertEqual(MrdsSection.mrds.title, "每日大赛")
        XCTAssertEqual(MrdsSection.aijc.title, "AI剧场")
    }

    func testListRoutesFollowTypechoPaging() {
        XCTAssertEqual(
            MrdsListContext.filter(.latest).pageURL(page: 1)?.absoluteString,
            "https://www.mrds66.com/"
        )
        XCTAssertEqual(
            MrdsListContext.filter(.latest).pageURL(page: 2)?.absoluteString,
            "https://www.mrds66.com/page/2/"
        )
        XCTAssertEqual(
            MrdsListContext.filter(.mrds).pageURL(page: 1)?.absoluteString,
            "https://www.mrds66.com/category/mrds/"
        )
        XCTAssertEqual(
            MrdsListContext.filter(.mrds).pageURL(page: 3)?.absoluteString,
            "https://www.mrds66.com/category/mrds/3/"
        )
        XCTAssertEqual(
            MrdsListContext.search("校园").pageURL(page: 1)?.absoluteString,
            "https://www.mrds66.com/search/%E6%A0%A1%E5%9B%AD/"
        )
        XCTAssertEqual(
            MrdsListContext.search("校园").pageURL(page: 2)?.absoluteString,
            "https://www.mrds66.com/search/%E6%A0%A1%E5%9B%AD/2/"
        )
        XCTAssertEqual(
            MrdsListContext.search("a+b").pageURL(page: 1)?.absoluteString,
            "https://www.mrds66.com/search/a%2Bb/"
        )
    }

    func testListParserSkipsAdsAndNormalizesCoverSlash() throws {
        let html = #"""
        <ol class="page-navigator">
          <li class="active"><a>1</a></li>
          <li><a href="/page/2/">2</a></li>
          <li class="next"><a href="/page/2/">下一页</a></li>
        </ol>
        <article id="post-card-191191">
          <div class="post-card-cover" onclick="loadBannerDirect('https://pic.sbhioa.cn//upload_01/cover.jpg')"></div>
          <a href="/archives/191191/"></a>
          <h2 class="post-card-title">校园写真</h2>
          <div><span>校园学生</span></div>
          <time itemprop="datePublished" content="2026-08-31">2026-08-31</time>
        </article>
        <article class="ad-item"><div id="post-card-1"></div></article>
        """#
        let page = try MrdsListResolver.parse(
            data: Data(html.utf8),
            context: .filter(.latest),
            requestedPage: 1
        )
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "191191")
        XCTAssertEqual(page.items[0].title, "校园写真")
        XCTAssertEqual(page.items[0].detailURL.absoluteString, "https://www.mrds66.com/archives/191191/")
        XCTAssertEqual(page.items[0].coverURL?.absoluteString, "https://pic.sbhioa.cn/upload_01/cover.jpg")
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.totalPages, 2)
        XCTAssertEqual(page.nextPageURL?.absoluteString, "https://www.mrds66.com/page/2/")
    }

    func testSearchArticleMarkupKeepsBannerCover() throws {
        let html = #"""
        <article itemscope itemtype="http://schema.org/BlogPosting" class="">
          <a href="/archives/191266/">
            <div class="post-card" id="post-card-191266">
              <div class="blog-background"></div>
              <script type="text/javascript">
                loadBannerDirect('https://pic.sbhioa.cn//upload_01/xiao/20260830/cover.jpeg', '', document.querySelector('#post-card-191266'), '-1');
              </script>
              <h2 class="post-card-title" itemprop="headline">校园写真搜索结果</h2>
              <div class="post-card-info">
                <span>每日大赛, 动漫之家</span>
              </div>
            </div>
          </a>
        </article>
        """#
        let page = try MrdsListResolver.parse(
            data: Data(html.utf8),
            context: .search("校园"),
            requestedPage: 1
        )
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "191266")
        XCTAssertEqual(page.items[0].title, "校园写真搜索结果")
        XCTAssertEqual(
            page.items[0].coverURL?.absoluteString,
            "https://pic.sbhioa.cn/upload_01/xiao/20260830/cover.jpeg"
        )
    }

    func testListParserFallsBackToPicHostWhenBannerHelperIsMissing() throws {
        let html = #"""
        <article>
          <div class="post-card" id="post-card-191266">
            <a href="/archives/191266/">
              <img src="https://pic.sbhioa.cn//upload_01/xiao/cover.jpeg">
              <h2 class="post-card-title">无 banner 助手</h2>
            </a>
          </div>
        </article>
        """#
        let page = try MrdsListResolver.parse(
            data: Data(html.utf8),
            context: .search("校园"),
            requestedPage: 1
        )
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(
            page.items[0].coverURL?.absoluteString,
            "https://pic.sbhioa.cn/upload_01/xiao/cover.jpeg"
        )
    }

    func testLiveSearchPageKeepsBannerCovers() throws {
        let url = URL(fileURLWithPath: "/tmp/mrds-search.html")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("Live search snapshot is not present")
        }
        let page = try MrdsListResolver.parse(
            data: Data(contentsOf: url),
            context: .search("校园"),
            requestedPage: 1
        )
        let missing = page.items.filter { $0.coverURL == nil }.map(\.id)
        XCTAssertFalse(page.items.isEmpty)
        XCTAssertEqual(missing, [], "parsed \(page.items.count) search items without covers: \(missing)")
    }

    func testDetailParserReadsHiddenImagesVideoAndNearLinks() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.mrds66.com/archives/191191/"))
        let html = #"""
        <meta property="og:description" content="图集说明">
        <div class="post-content" itemprop="articleBody">
          <img src="/usr/plugins/tbxw/zw.png" data-xkrkllgl="https://pic.sbhioa.cn/a.jpg">
          <img src="/usr/plugins/tbxw/zw.png" data-xkrkllgl="https://pic.sbhioa.cn/b.jpg">
          <img src="/usr/plugins/tbxw/zw.png" data-xkrkllgl="https://evil.example/c.jpg">
        </div>
        <div data-video_tag_name="校园,写真"></div>
        <script>var cfg={"video":{"url":"https:\/\/hls.piotrt.cn\/play\/index.m3u8","type":"hls"}};</script>
        <div class="post-near">
          <a href="/archives/191190/" title="上一篇"></a>
          <a href="/archives/191192/" title="下一篇写真"></a>
          <a href="https://www.mrds66.com/archives/191191/" title="当前"></a>
        </div>
        """#
        let page = try MrdsDetailResolver.parse(html: html, pageURL: pageURL)
        XCTAssertEqual(page.imageURLs.map(\.absoluteString), [
            "https://pic.sbhioa.cn/a.jpg",
            "https://pic.sbhioa.cn/b.jpg",
        ])
        XCTAssertEqual(page.videoURL?.absoluteString, "https://hls.piotrt.cn/play/index.m3u8")
        XCTAssertEqual(page.metadata?.description, "图集说明")
        XCTAssertEqual(page.metadata?.tags, ["校园", "写真"])
        XCTAssertEqual(page.recommendations.map(\.title), ["上一篇", "下一篇写真"])
        XCTAssertTrue(page.recommendations.allSatisfy { $0.coverURL == nil })
        XCTAssertEqual(
            page.recommendations.map(\.detailURL.absoluteString),
            [
                "https://www.mrds66.com/archives/191190/",
                "https://www.mrds66.com/archives/191192/",
            ]
        )
    }

    func testDetailParserKeepsHLSQueryString() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.mrds66.com/archives/191191/"))
        let html = #"""
        <div class="post-content" itemprop="articleBody">
          <img src="/usr/plugins/tbxw/zw.png" data-xkrkllgl="https://pic.sbhioa.cn/a.jpg">
        </div>
        <script>var cfg={"video":{"url":"https:\/\/hls.piotrt.cn\/play\/index.m3u8?auth_key=abc%2Fdef","type":"hls"}};</script>
        """#
        let page = try MrdsDetailResolver.parse(html: html, pageURL: pageURL)
        XCTAssertEqual(
            page.videoURL?.absoluteString,
            "https://hls.piotrt.cn/play/index.m3u8?auth_key=abc%2Fdef"
        )
    }

    func testRecommendationCoverPrefersBannerThenHiddenImage() throws {
        let pageURL = try XCTUnwrap(URL(string: "https://www.mrds66.com/archives/191190/"))
        let html = #"""
        <div class="post-card-cover" onclick="loadBannerDirect('https://pic.sbhioa.cn//upload_01/cover.jpg')"></div>
        <div class="post-content" itemprop="articleBody">
          <img src="/usr/plugins/tbxw/zw.png" data-xkrkllgl="https://pic.sbhioa.cn/first.jpg">
        </div>
        """#
        XCTAssertEqual(
            MrdsDetailResolver.coverURL(fromArchiveHTML: html, pageURL: pageURL)?.absoluteString,
            "https://pic.sbhioa.cn/upload_01/cover.jpg"
        )

        let fallbackHTML = #"""
        <div class="post-content" itemprop="articleBody">
          <img src="/usr/plugins/tbxw/zw.png" data-xkrkllgl="https://pic.sbhioa.cn/first.jpg">
        </div>
        <meta property="og:image" content="https://www.mrds66.com/usr/themes/Mirages/images/social.jpg">
        """#
        XCTAssertEqual(
            MrdsDetailResolver.coverURL(fromArchiveHTML: fallbackHTML, pageURL: pageURL)?.absoluteString,
            "https://pic.sbhioa.cn/first.jpg"
        )
    }

    @MainActor
    func testSwitchingSectionRestoresCachedListImmediately() async throws {
        let latest = try MrdsGalleryItem(
            id: "1",
            title: "最新",
            rawTitle: "最新",
            category: "最近更新",
            publishedDate: "",
            detailURL: XCTUnwrap(URL(string: "https://www.mrds66.com/archives/1/")),
            coverURL: URL(string: "https://pic.sbhioa.cn/latest.jpg"),
            coverAspectRatio: 1.6,
            hasVideo: false
        )
        let category = try MrdsGalleryItem(
            id: "2",
            title: "分类",
            rawTitle: "分类",
            category: "每日大赛",
            publishedDate: "",
            detailURL: XCTUnwrap(URL(string: "https://www.mrds66.com/archives/2/")),
            coverURL: URL(string: "https://pic.sbhioa.cn/mrds.jpg"),
            coverAspectRatio: 1.6,
            hasVideo: false
        )
        let pages: [MrdsListContext: MrdsListPage] = [
            .filter(.latest): MrdsListPage(items: [latest], currentPage: 1, totalPages: 1, nextPageURL: nil),
            .filter(.mrds): MrdsListPage(items: [category], currentPage: 1, totalPages: 1, nextPageURL: nil),
        ]
        let store = MrdsGalleryStore(
            favorites: FavoritesStore(),
            listResolver: { context, _ in
                guard let page = pages[context] else { throw MrdsListResolverError.invalidURL }
                return page
            }
        )

        store.refreshFromNetwork()
        await waitUntil(store.items.map(\.id) == ["1"])
        store.setFilter(.mrds)
        await waitUntil(store.items.map(\.id) == ["2"])
        store.setFilter(.latest)
        XCTAssertEqual(store.items.map(\.id), ["1"])
    }

    @MainActor
    private func waitUntil(_ condition: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 50 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for store state", file: file, line: line)
    }

    @MainActor
    func testDetailRejectsNonArchivePaths() async {
        let url = try? XCTUnwrap(URL(string: "https://www.mrds66.com/category/mrds/"))
        guard let url else { return }
        do {
            _ = try await MrdsDetailResolver.resolve(pageURL: url)
            XCTFail("Category URL should not resolve as a detail page")
        } catch MrdsDetailResolverError.invalidDetailURL {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testPolicyAllowsOnlyTrustedMrdsHosts() throws {
        let html = try XCTUnwrap(URL(string: "https://www.mrds66.com/archives/1/"))
        let cover = try XCTUnwrap(URL(string: "https://pic.sbhioa.cn/upload_01/cover.jpg"))
        let playlist = try XCTUnwrap(URL(string: "https://hls.piotrt.cn/play/index.m3u8"))
        let segment = try XCTUnwrap(URL(string: "https://ts.syjiaotong.mobi/seg.ts"))
        let doudou = try XCTUnwrap(URL(string: "https://tx.doudou520.online/play/crypt.key"))
        let zhixun = try XCTUnwrap(URL(string: "https://ts.zhixunkeji.xyz/play/segment.ts"))
        let lookalike = try XCTUnwrap(URL(string: "https://mrds66.com.evil.example/archives/1/"))
        let mirror = try XCTUnwrap(URL(string: "https://www.mrdsw15.com/archives/1/"))
        let insecure = try XCTUnwrap(URL(string: "http://www.mrds66.com/archives/1/"))
        let untrustedMedia = try XCTUnwrap(URL(string: "https://cdn.evil.example/seg.ts"))

        XCTAssertTrue(OnlineSourcePolicy.allows(html, source: .mrds, resource: .html))
        XCTAssertTrue(OnlineSourcePolicy.allows(cover, source: .mrds, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(playlist, source: .mrds, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(segment, source: .mrds, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(doudou, source: .mrds, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(zhixun, source: .mrds, resource: .media))
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: cover), .mrds)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: doudou), .mrds)
        XCTAssertFalse(OnlineSourcePolicy.allows(lookalike, source: .mrds, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(mirror, source: .mrds, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(insecure, source: .mrds, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(untrustedMedia, source: .mrds, resource: .media))
        XCTAssertThrowsError(try MrdsRequestFactory.makeHTMLRequest(url: lookalike))
    }

    @MainActor
    func testFavoritesBridgeRejectsUntrustedRecords() throws {
        let allowed = FavoriteRecord(
            id: "mrds:1",
            sourceID: "mrds",
            title: "校园",
            rawTitle: "校园",
            subtitle: "校园学生",
            detailURL: "https://www.mrds66.com/archives/191191/",
            coverURL: "https://pic.sbhioa.cn/cover.jpg",
            imageCount: 12,
            pageCount: 1
        )
        let rejected = FavoriteRecord(
            id: "mrds:evil",
            sourceID: "mrds",
            title: "evil",
            rawTitle: "evil",
            subtitle: "",
            detailURL: "https://mrds66.com.evil.example/archives/1/",
            coverURL: "https://evil.example/cover.jpg",
            imageCount: 1,
            pageCount: 1
        )
        let item = try XCTUnwrap(MrdsFavoritesBridge.item(from: allowed))
        XCTAssertEqual(item.id, "191191")
        XCTAssertEqual(item.coverURL?.absoluteString, "https://pic.sbhioa.cn/cover.jpg")
        XCTAssertNil(MrdsFavoritesBridge.item(from: rejected))
    }

    @MainActor
    func testEncryptedCoverBytesDecryptToJPEG() throws {
        let jpeg = try XCTUnwrap(tinyJPEGData())
        XCTAssertTrue(MrdsImageDecryptor.isImageMagic(jpeg))
        let cipher = try XCTUnwrap(MrdsImageDecryptor.encryptForTesting(jpeg))
        XCTAssertFalse(MrdsImageDecryptor.isImageMagic(cipher))
        XCTAssertEqual(cipher.count % 16, 0)

        let plain = try XCTUnwrap(MrdsImageDecryptor.plaintext(from: cipher))
        XCTAssertTrue(MrdsImageDecryptor.isImageMagic(plain))
        XCTAssertEqual(plain.prefix(3), Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(MrdsImageDecryptor.plaintext(from: jpeg), jpeg)
        XCTAssertNil(MrdsImageDecryptor.plaintext(from: Data(repeating: 7, count: 64)))
    }

    @MainActor
    func testImageMapperClaimsPicHostAfterPrepare() throws {
        MrdsImageDecryptor.prepare()
        let pic = try XCTUnwrap(URL(string: "https://pic.sbhioa.cn/upload_01/cover.jpg"))
        let other = try XCTUnwrap(URL(string: "https://r2-media.knit.bid/cover.jpg"))
        XCTAssertTrue(RemoteImageResponseMapper.matches(pic))
        XCTAssertFalse(RemoteImageResponseMapper.matches(other))

        let jpeg = try XCTUnwrap(tinyJPEGData())
        let cipher = try XCTUnwrap(MrdsImageDecryptor.encryptForTesting(jpeg))
        let mapped = try XCTUnwrap(RemoteImageResponseMapper.mappedData(for: pic, from: cipher))
        XCTAssertTrue(MrdsImageDecryptor.isImageMagic(mapped))
        XCTAssertEqual(RemoteImageResponseMapper.mappedData(for: other, from: cipher), cipher)
    }

    private func tinyJPEGData() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.representation(using: .jpeg, properties: [:])
    }
}
