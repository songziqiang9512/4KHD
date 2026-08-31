@testable import _KHD
import XCTest

final class PornyGalleryTests: XCTestCase {
    func testSidebarSectionsKeepPublicNavOrder() {
        XCTAssertEqual(
            PornySection.allCases.map(\.rawValue),
            [
                "latest", "hd", "recent-favorite", "hot-list", "recent-rating", "nonpaid",
                "ori", "long-list", "longer-list", "month-discuss", "top-favorite",
                "most-favorite", "top-list", "top-last",
            ]
        )
        XCTAssertEqual(PornySection.latest.title, "最近更新")
        XCTAssertEqual(PornySection.topLast.title, "上月最热")
        XCTAssertEqual(
            PornySection.latest.listURL(searchQuery: nil)?.absoluteString,
            "https://91porny.com/video/category/latest"
        )
        XCTAssertEqual(
            PornySection.latest.listURL(searchQuery: "hello")?.absoluteString,
            "https://91porny.com/search?keywords=hello"
        )
    }

    func testListParserKeepsVideoCardsAndSkipsAds() throws {
        let html = """
        <div class="colVideoList">
          <div class="video-elem">
            <a target="_self" class="display d-block" href="/video/view/3b01932c8964c074999a">
              <div class="img" style="background-image: url('//int.ucloud161.xyz/thumb/1238534.jpg')"></div>
              <small class="layer">00:04:03</small>
            </a>
            <a target="_self" class="title text-sub-title mt-2 mb-1" href="/video/view/3b01932c8964c074999a">英语实习老师</a>
          </div>
        </div>
        <div class="colVideoList">
          <div class="video-elem">
            <a target="_blank" class="display" href="https://8743.w87434799.vip/?cid=9738938">
              <div class="img" style="background-image: url('https://txdy.mczsok.com/999/x5yd5g73t402.gif')"></div>
              <small class="layer">18:18</small>
            </a>
            <a class="title" href="https://8743.w87434799.vip/?cid=9738938">送888元</a>
          </div>
        </div>
        <ul class="pagination">
          <li class="page-item active" aria-current="page"><span class="page-link">1</span></li>
          <li class="page-item"><a class="page-link" href="/video/category/latest/2">2</a></li>
          <li class="page-item"><a class="page-link" href="/video/category/latest/6557">6557</a></li>
          <li class="page-item"><a class="page-link" href="/video/category/latest/2">&raquo;</a></li>
        </ul>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://91porny.com/video/category/latest"))
        let page = try PornyListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.map(\.id), ["3b01932c8964c074999a"])
        XCTAssertEqual(page.items.first?.title, "英语实习老师")
        XCTAssertEqual(page.items.first?.durationText, "00:04:03")
        XCTAssertEqual(
            page.items.first?.coverURL?.absoluteString,
            "https://int.ucloud161.xyz/thumb/1238534.jpg"
        )
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.totalPages, 6557)
        XCTAssertEqual(
            page.nextPageURL?.absoluteString,
            "https://91porny.com/video/category/latest/2"
        )
    }

    func testHDListParserKeepsViewHDCardsAndSkipsAds() throws {
        let html = """
        <div class="colVideoList">
          <div class="video-elem">
            <a target="_self" class="display d-block" href="/video/viewhd/7fa21c9ab0">
              <div class="img" style="background-image: url('//int.ucloud161.xyz/thumb/9.jpg')"></div>
              <small class="layer">00:12:01</small>
            </a>
            <a target="_self" class="title text-sub-title mt-2 mb-1" href="/video/viewhd/7fa21c9ab0">高清条目</a>
          </div>
        </div>
        <div class="colVideoList">
          <div class="video-elem mb-3">
            <a target="_blank" class="display" href="https://8743.w87434799.vip/?cid=1">
              <div class="img" style="background-image: url('https://txdy.mczsok.com/999/ad.gif')"></div>
            </a>
            <a class="title" href="https://8743.w87434799.vip/?cid=1">广告</a>
          </div>
        </div>
        <ul class="pagination">
          <li class="page-item active"><span class="page-link">1</span></li>
          <li class="page-item"><a class="page-link" href="/video/category/hd/2">&raquo;</a></li>
        </ul>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://91porny.com/video/category/hd"))
        let page = try PornyListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.map(\.id), ["7fa21c9ab0"])
        XCTAssertEqual(
            page.items.first?.detailURL.absoluteString,
            "https://91porny.com/video/viewhd/7fa21c9ab0"
        )
        XCTAssertEqual(page.items.first?.title, "高清条目")
        XCTAssertEqual(
            page.nextPageURL?.absoluteString,
            "https://91porny.com/video/category/hd/2"
        )
    }

    func testDetailParserReadsPublicDataSrcAndRejectsMissingPlaylist() throws {
        let html = """
        <video id="video-play" data-src="https://cdn2.jiuse3.cloud/hls/1237947/index.m3u8?t=1&amp;m=abc"></video>
        <meta property="og:image" content="https://int.ucloud161.xyz/thumb/1237947.jpg" />
        """
        let pageURL = try XCTUnwrap(URL(string: "https://91porny.com/video/view/3b01932c8964c074999a"))
        let detail = try PornyDetailResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(
            detail.videoURL.absoluteString,
            "https://cdn2.jiuse3.cloud/hls/1237947/index.m3u8?t=1&m=abc"
        )
        XCTAssertEqual(detail.coverURL?.absoluteString, "https://int.ucloud161.xyz/thumb/1237947.jpg")

        XCTAssertThrowsError(
            try PornyDetailResolver.parse(
                data: Data("<html>login wall</html>".utf8),
                pageURL: pageURL
            )
        ) { error in
            XCTAssertEqual(error as? PornyDetailResolverError, .missingPlaylist)
        }

        let vipHTML = """
        <video id="video-play" data-src="//cdn2.jiuse2.cloud/hlsd/js10/index.m3u8"></video>
        """
        XCTAssertThrowsError(
            try PornyDetailResolver.parse(data: Data(vipHTML.utf8), pageURL: pageURL)
        ) { error in
            XCTAssertEqual(error as? PornyDetailResolverError, .missingPlaylist)
        }

        let httpCoverHTML = """
        <video id="video-play" data-src="https://cdn2.jiuse3.cloud/hls/1237947/index.m3u8?t=1&amp;m=abc"></video>
        <meta property="og:image" content="http://int.ucloud161.xyz/thumb/1237947.jpg" />
        """
        let httpCover = try PornyDetailResolver.parse(data: Data(httpCoverHTML.utf8), pageURL: pageURL)
        XCTAssertEqual(httpCover.coverURL?.absoluteString, "https://int.ucloud161.xyz/thumb/1237947.jpg")
    }

    func testViewHDPlaybackUsesPublicViewPath() throws {
        let hd = try XCTUnwrap(URL(string: "https://91porny.com/video/viewhd/09e9ddd294623b556bf3"))
        let view = try XCTUnwrap(URL(string: "https://91porny.com/video/view/09e9ddd294623b556bf3"))
        let lookalike = try XCTUnwrap(URL(string: "https://91porny.com.evil.example/video/viewhd/abc"))
        XCTAssertEqual(
            PornyDetailResolver.publicPlaybackURL(from: hd)?.absoluteString,
            "https://91porny.com/video/view/09e9ddd294623b556bf3"
        )
        XCTAssertNil(PornyDetailResolver.publicPlaybackURL(from: view))
        XCTAssertNil(PornyDetailResolver.publicPlaybackURL(from: lookalike))
    }

    func testPolicyRejectsLookalikeHosts() throws {
        let html = try XCTUnwrap(URL(string: "https://91porny.com/video/view/abc"))
        let lookalike = try XCTUnwrap(URL(string: "https://91porny.com.evil.example/video/view/abc"))
        let thumb = try XCTUnwrap(URL(string: "https://int.ucloud161.xyz/thumb/1.jpg"))
        let qiniu = try XCTUnwrap(URL(string: "https://int.qiniuyun37.xyz/thumb/1.jpg"))
        let playlist = try XCTUnwrap(URL(string: "https://cdn2.jiuse3.cloud/hls/1/index.m3u8"))
        let ad = try XCTUnwrap(URL(string: "https://txdy.mczsok.com/999/x.gif"))
        let teaser = try XCTUnwrap(URL(string: "https://cdn2.jiuse2.cloud/hlsd/js10/index.m3u8"))

        XCTAssertTrue(OnlineSourcePolicy.allows(html, source: .porny, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(lookalike, source: .porny, resource: .html))
        XCTAssertTrue(OnlineSourcePolicy.allows(thumb, source: .porny, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(qiniu, source: .porny, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(playlist, source: .porny, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(ad, source: .porny, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(teaser, source: .porny, resource: .media))
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: thumb), .porny)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: playlist), .porny)
    }

    func testFavoritesBridgeRequiresViewPath() throws {
        let item = try OnlineVideoItem(
            id: "3b01932c8964c074999a",
            title: "Demo",
            subtitle: "91PORNY",
            detailURL: XCTUnwrap(URL(string: "https://91porny.com/video/view/3b01932c8964c074999a")),
            coverURL: XCTUnwrap(URL(string: "https://int.ucloud161.xyz/thumb/1.jpg")),
            coverAspectRatio: 16.0 / 9.0,
            durationText: "00:04:03"
        )
        let record = PornyFavoritesBridge.record(from: item)
        XCTAssertEqual(FavoriteSource.source(for: record), .porny)
        XCTAssertEqual(PornyFavoritesBridge.item(from: record)?.id, "3b01932c8964c074999a")
        let hdRecord = try PornyFavoritesBridge.record(from: OnlineVideoItem(
            id: "7fa21c9ab0",
            title: "HD",
            subtitle: "91PORNY",
            detailURL: XCTUnwrap(URL(string: "https://91porny.com/video/viewhd/7fa21c9ab0")),
            coverURL: nil,
            coverAspectRatio: 16.0 / 9.0,
            durationText: ""
        ))
        XCTAssertEqual(PornyFavoritesBridge.item(from: hdRecord)?.id, "7fa21c9ab0")
        XCTAssertNil(PornyFavoritesBridge.item(from: FavoriteRecord(
            id: "porny:x", sourceID: "porny", title: "x", rawTitle: "x", subtitle: "",
            detailURL: "https://91porny.com/videos/x", coverURL: nil, imageCount: 0, pageCount: 1
        )))
    }
}
