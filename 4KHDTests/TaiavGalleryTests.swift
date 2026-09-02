@testable import _KHD
import XCTest

final class TaiavGalleryTests: XCTestCase {
    func testSidebarSectionsKeepDiscoverOrder() throws {
        XCTAssertEqual(
            TaiavSection.allCases.map(\.rawValue),
            ["latest", "无码", "有码", "国产AV", "网红主播"]
        )
        XCTAssertEqual(TaiavSection.latest.title, "最近更新")
        XCTAssertEqual(TaiavSection.uncensored.title, "无码")
        XCTAssertEqual(
            TaiavSection.latest.listURL(searchQuery: nil)?.absoluteString,
            "https://taiav.com/cn"
        )
        XCTAssertEqual(
            TaiavSection.uncensored.listURL(searchQuery: nil)?.absoluteString,
            "https://taiav.com/cn/category/%E6%97%A0%E7%A0%81"
        )
        let search = try XCTUnwrap(TaiavSection.latest.listURL(searchQuery: "糖心"))
        XCTAssertEqual(search.scheme, "https")
        XCTAssertEqual(search.host, "taiav.com")
        XCTAssertEqual(search.path, "/cn/search")
        XCTAssertTrue(search.absoluteString.contains("q=%E7%B3%96%E5%BF%83"))
        XCTAssertFalse(search.absoluteString.contains("糖心"))
    }

    func testListParserKeepsMovieCardsSkipsAdsAndReadsPagination() throws {
        let html = """
        <div data-id='"6a86be1576e3ea4a1d6ca7ac"' class="movie-card">
          <a href="/cn/movie/6a86be1576e3ea4a1d6ca7ac">
            <img src="https://img.storyofthepast.xyz/videos/202608/20/6a86be1576e3ea4a1d6ca7ac/poster2.webp" alt="公开条目" />
          </a>
          <a href="/cn/movie/6a86be1576e3ea4a1d6ca7ac">
            <h5 data-full-title="公开条目完整标题">公开条目</h5>
          </a>
        </div>
        <div class="movie-card">
          <a href="/file/ad123">
            <img src="https://img.storyofthepast.xyz/file/ad.gif" alt="廣告" />
          </a>
        </div>
        <li class="hots-card"><a href="/cn/movie/66846ff2f40c787c969d3c85">
          <img src="https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/poster2.jpg" alt="推荐" />
        </a></li>
        <ul class="pagination">
          <li class="page-item active"><a class="page-link" href="?page=1">1</a></li>
          <li class="page-item"><a class="page-link" href="?page=2">2</a></li>
          <li class="page-item"><a class="page-link" href="?page=2">&raquo;</a></li>
          <li class="page-item"><a class="page-link" href="?page=169">尾页</a></li>
        </ul>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://taiav.com/cn/category/%E6%97%A0%E7%A0%81"))
        let page = try TaiavListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.map(\.id), ["6a86be1576e3ea4a1d6ca7ac"])
        XCTAssertEqual(page.items.first?.title, "公开条目完整标题")
        XCTAssertEqual(
            page.items.first?.detailURL.absoluteString,
            "https://taiav.com/cn/movie/6a86be1576e3ea4a1d6ca7ac"
        )
        XCTAssertEqual(
            page.items.first?.coverURL?.absoluteString,
            "https://img.storyofthepast.xyz/videos/202608/20/6a86be1576e3ea4a1d6ca7ac/poster2.webp"
        )
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.totalPages, 169)
        XCTAssertEqual(
            page.nextPageURL?.absoluteString,
            "https://taiav.com/cn/category/%E6%97%A0%E7%A0%81?page=2"
        )
    }

    func testHomePageHasNoNextPage() throws {
        let html = """
        <div class="movie-card">
          <a href="/cn/movie/66846ff2f40c787c969d3c85">
            <img src="https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/poster2.jpg" alt="首页条目" />
          </a>
        </div>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://taiav.com/cn"))
        let page = try TaiavListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.map(\.id), ["66846ff2f40c787c969d3c85"])
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.totalPages, 1)
        XCTAssertNil(page.nextPageURL)
    }

    func testSearchPaginationKeepsEncodedQuery() throws {
        let html = """
        <div class="movie-card">
          <a href="/cn/movie/6a86be1576e3ea4a1d6ca7ac">
            <img src="https://img.storyofthepast.xyz/videos/202608/20/6a86be1576e3ea4a1d6ca7ac/poster2.webp" alt="搜索条目" />
          </a>
        </div>
        <ul class="pagination">
          <li class="page-item active"><a href="?q=%E7%B3%96%E5%BF%83&page=1">1</a></li>
          <li class="page-item"><a href="?q=%E7%B3%96%E5%BF%83&page=2">&raquo;</a></li>
        </ul>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://taiav.com/cn/search?q=%E7%B3%96%E5%BF%83"))
        let page = try TaiavListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(
            page.nextPageURL?.absoluteString,
            "https://taiav.com/cn/search?q=%E7%B3%96%E5%BF%83&page=2"
        )
    }

    func testGetMovieParserResolvesRelativePlaylistOntoMediaHost() throws {
        let movieID = "66846ff2f40c787c969d3c85"
        let json = """
        {"m3u8":"/videos/202407/03/66846ff2f40c787c969d3c85/7f3b68/index.m3u8?random=abc&counts=5&timestamp=1&key=def","message":"ok"}
        """
        let detail = try TaiavDetailResolver.parse(data: Data(json.utf8), movieID: movieID)
        XCTAssertEqual(
            detail.videoURL.absoluteString,
            "https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/7f3b68/index.m3u8?random=abc&counts=5&timestamp=1&key=def"
        )
        XCTAssertNil(detail.coverURL)
    }

    func testGetMovieParserRejectsMissingWrongHostAndCrossItemPlaylist() throws {
        let movieID = "66846ff2f40c787c969d3c85"
        XCTAssertThrowsError(
            try TaiavDetailResolver.parse(data: Data("<html>home</html>".utf8), movieID: movieID)
        ) { error in
            XCTAssertEqual(error as? TaiavDetailResolverError, .invalidPayload)
        }
        XCTAssertThrowsError(
            try TaiavDetailResolver.parse(data: Data(#"{"message":"buy"}"#.utf8), movieID: movieID)
        ) { error in
            XCTAssertEqual(error as? TaiavDetailResolverError, .missingPlaylist)
        }
        XCTAssertThrowsError(
            try TaiavDetailResolver.parse(
                data: Data(#"{"m3u8":"/videos/202407/03/aaaaaaaaaaaaaaaaaaaaaaaa/index.m3u8"}"#.utf8),
                movieID: movieID
            )
        ) { error in
            XCTAssertEqual(error as? TaiavDetailResolverError, .missingPlaylist)
        }
        XCTAssertThrowsError(
            try TaiavDetailResolver.parse(
                data: Data(#"{"m3u8":"https://taiav.com/videos/202407/03/66846ff2f40c787c969d3c85/index.m3u8"}"#.utf8),
                movieID: movieID
            )
        ) { error in
            XCTAssertEqual(error as? TaiavDetailResolverError, .missingPlaylist)
        }
    }

    func testMovieIDRequiresSimplifiedChineseWatchPath() throws {
        let watch = try XCTUnwrap(URL(string: "https://taiav.com/cn/movie/66846ff2f40c787c969d3c85"))
        let english = try XCTUnwrap(URL(string: "https://taiav.com/en/movie/66846ff2f40c787c969d3c85"))
        let buy = try XCTUnwrap(URL(string: "https://taiav.com/cn/login"))
        XCTAssertEqual(TaiavFavoritesBridge.movieID(from: watch), "66846ff2f40c787c969d3c85")
        XCTAssertNil(TaiavFavoritesBridge.movieID(from: english))
        XCTAssertNil(TaiavFavoritesBridge.movieID(from: buy))
        XCTAssertEqual(
            TaiavRequestFactory.getMovieURL(movieID: "66846ff2f40c787c969d3c85")?.absoluteString,
            "https://taiav.com/api/getmovie?type=1280&id=66846ff2f40c787c969d3c85"
        )
    }

    func testPolicyRejectsLookalikeHostsPurchaseAPIsAndSisterSites() throws {
        let html = try XCTUnwrap(URL(string: "https://taiav.com/cn/movie/66846ff2f40c787c969d3c85"))
        let lookalike = try XCTUnwrap(URL(string: "https://taiav.com.evil.example/cn/movie/abc"))
        let getmovie = try XCTUnwrap(URL(string: "https://taiav.com/api/getmovie?type=1280&id=66846ff2f40c787c969d3c85"))
        let buymovie = try XCTUnwrap(URL(string: "https://taiav.com/api/buymovie"))
        let checkin = try XCTUnwrap(URL(string: "https://taiav.com/api/checkin"))
        let cover = try XCTUnwrap(URL(string: "https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/poster2.jpg"))
        let playlist = try XCTUnwrap(URL(string: "https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/index.m3u8"))
        let key = try XCTUnwrap(URL(string: "https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/ts.key"))
        let segment = try XCTUnwrap(URL(string: "https://v11cdn.snmovie.com/hls/seg0.ts"))
        let sister = try XCTUnwrap(URL(string: "https://storyofthepast.xyz/videos/1.jpg"))
        let mirror = try XCTUnwrap(URL(string: "https://bangerspis.xyz/cn"))

        XCTAssertTrue(OnlineSourcePolicy.allows(html, source: .taiav, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(lookalike, source: .taiav, resource: .html))
        XCTAssertTrue(OnlineSourcePolicy.allows(getmovie, source: .taiav, resource: .api))
        XCTAssertFalse(OnlineSourcePolicy.allows(buymovie, source: .taiav, resource: .api))
        XCTAssertFalse(OnlineSourcePolicy.allows(checkin, source: .taiav, resource: .api))
        XCTAssertTrue(OnlineSourcePolicy.allows(cover, source: .taiav, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(playlist, source: .taiav, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(key, source: .taiav, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(segment, source: .taiav, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(sister, source: .taiav, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(mirror, source: .taiav, resource: .html))
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: cover), .taiav)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: segment), .taiav)
    }

    func testFavoritesBridgeRequiresWatchPathAndTrustedCover() throws {
        let item = try OnlineVideoItem(
            id: "66846ff2f40c787c969d3c85",
            title: "Demo",
            subtitle: "TaiAV",
            detailURL: XCTUnwrap(URL(string: "https://taiav.com/cn/movie/66846ff2f40c787c969d3c85")),
            coverURL: XCTUnwrap(URL(string: "https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/poster2.jpg")),
            coverAspectRatio: 16.0 / 9.0,
            durationText: ""
        )
        let record = TaiavFavoritesBridge.record(from: item)
        XCTAssertEqual(FavoriteSource.source(for: record), .taiav)
        XCTAssertEqual(TaiavFavoritesBridge.item(from: record)?.id, "66846ff2f40c787c969d3c85")
        XCTAssertNil(TaiavFavoritesBridge.item(from: FavoriteRecord(
            id: "taiav:x", sourceID: "taiav", title: "x", rawTitle: "x", subtitle: "",
            detailURL: "https://taiav.com/en/movie/66846ff2f40c787c969d3c85", coverURL: nil, imageCount: 0, pageCount: 1
        )))
    }

    func testAES128KeyResolvesOnMediaHost() throws {
        let playlist = """
        #EXTM3U
        #EXT-X-KEY:METHOD=AES-128,URI="ts.key"
        #EXTINF:4.0,
        https://v11cdn.snmovie.com/hls/seg0.ts
        """
        let media = try XCTUnwrap(
            URL(string: "https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/index.m3u8")
        )
        let aes = KnitHLSPlaylist.playbackAES128(playlist, baseURL: media, source: .taiav)
        XCTAssertEqual(
            aes?.keyURL.absoluteString,
            "https://img.storyofthepast.xyz/videos/202407/03/66846ff2f40c787c969d3c85/ts.key"
        )
        XCTAssertEqual(aes?.defaultIV.count, 16)
    }
}
