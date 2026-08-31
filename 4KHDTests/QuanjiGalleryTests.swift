@testable import _KHD
import XCTest

final class QuanjiGalleryTests: XCTestCase {
    func testSidebarSectionsKeepPublicNavOrder() {
        XCTAssertEqual(QuanjiSection.allCases.map(\.rawValue), ["home", "boutique", "amateur"])
        XCTAssertEqual(QuanjiSection.home.title, "最近更新")
        XCTAssertEqual(QuanjiSection.boutique.title, "国产精品")
        XCTAssertEqual(
            QuanjiSection.boutique.listURL(searchQuery: nil)?.absoluteString,
            "https://91quanji.com/tag.jsp?t=5y9kg97rdzxe"
        )
        XCTAssertEqual(
            QuanjiSection.home.listURL(searchQuery: "hello")?.absoluteString,
            "https://91quanji.com/search.jsp?keyword=hello"
        )
    }

    func testListParserReadsCardsAndOpaqueNextPage() throws {
        let html = """
        <div class="item thumb thumb--videos">
          <a href="watch.jsp?v=wxkgwvpwo2m6" target="_blank">
            <div class="thumb__img">
              <img src="https://pics.mugua01.cfd/3/ab/df/a2/cover.jpg" style="object-fit:cover" />
            </div>
            <h5 class="thumb-spot__title">河北燕山大学</h5>
          </a>
        </div>
        <div class="item thumb thumb--videos">
          <a href="watch.jsp?v=1mqglymkvrj3" target="_blank">
            <div class="thumb__img">
              <img src="https://pics.mugua01.cfd/7/34/fb/a3/cover2.jpg" />
            </div>
            <h5 class="thumb-spot__title">白金泄密</h5>
          </a>
        </div>
        <ul class="pagination">
          <li class="active"><a>1</a></li>
          <li><a href="?t=5y9kg97rdzxe&p=g6r2m3qyq70x">2</a></li>
          <li><a href="?t=5y9kg97rdzxe&p=qr9ew00own3x">45</a></li>
          <li><a href="?t=5y9kg97rdzxe&p=g6r2m3qyq70x"><i class="icon-chevron-right"></i></a></li>
        </ul>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://91quanji.com/tag.jsp?t=5y9kg97rdzxe"))
        let page = try QuanjiListResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(page.items.map(\.id), ["wxkgwvpwo2m6", "1mqglymkvrj3"])
        XCTAssertEqual(page.items.first?.title, "河北燕山大学")
        XCTAssertEqual(
            page.items.first?.coverURL?.absoluteString,
            "https://pics.mugua01.cfd/3/ab/df/a2/cover.jpg"
        )
        XCTAssertEqual(page.currentPage, 1)
        XCTAssertEqual(page.totalPages, 45)
        XCTAssertEqual(
            page.nextPageURL?.absoluteString,
            "https://91quanji.com/tag.jsp?t=5y9kg97rdzxe&p=g6r2m3qyq70x"
        )
    }

    func testDetailParserDecodesPublicXORPlaylist() throws {
        let playlist = "https://8017.o9hx3f-s8jamrmtps5.sbs/9/e8/chunklist_w.m3u8?v=token"
        let encoded = xor80("url: '\(playlist)'")
        let html = """
        <html><body>
        <img src="https://pics.mugua01.cfd/6/80/d3/4d/cover.jpg" />
        <script>eval(I("\(encoded)"))</script>
        </body></html>
        """
        let pageURL = try XCTUnwrap(URL(string: "https://91quanji.com/watch.jsp?v=6yo27nn31g08"))
        let detail = try QuanjiDetailResolver.parse(data: Data(html.utf8), pageURL: pageURL)
        XCTAssertEqual(detail.videoURL.absoluteString, playlist)
        XCTAssertEqual(detail.coverURL?.absoluteString, "https://pics.mugua01.cfd/6/80/d3/4d/cover.jpg")
    }

    func testPolicyRejectsLookalikeHosts() throws {
        let html = try XCTUnwrap(URL(string: "https://91quanji.com/watch.jsp?v=abc"))
        let lookalike = try XCTUnwrap(URL(string: "https://91quanji.com.evil.example/watch.jsp?v=abc"))
        let thumb = try XCTUnwrap(URL(string: "https://pics.mugua01.cfd/cover.jpg"))
        let playlist = try XCTUnwrap(URL(string: "https://8017.o9hx3f-s8jamrmtps5.sbs/a/chunklist_w.m3u8"))
        let otherCDN = try XCTUnwrap(URL(string: "https://evil.example/chunklist_w.m3u8"))

        XCTAssertTrue(OnlineSourcePolicy.allows(html, source: .quanji, resource: .html))
        XCTAssertFalse(OnlineSourcePolicy.allows(lookalike, source: .quanji, resource: .html))
        XCTAssertTrue(OnlineSourcePolicy.allows(thumb, source: .quanji, resource: .media))
        XCTAssertTrue(OnlineSourcePolicy.allows(playlist, source: .quanji, resource: .media))
        XCTAssertFalse(OnlineSourcePolicy.allows(otherCDN, source: .quanji, resource: .media))
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: thumb), .quanji)
        XCTAssertEqual(OnlineSourcePolicy.source(forMediaURL: playlist), .quanji)
    }

    func testFavoritesBridgeRequiresWatchQuery() throws {
        let item = try OnlineVideoItem(
            id: "6yo27nn31g08",
            title: "Demo",
            subtitle: "木瓜视频",
            detailURL: XCTUnwrap(URL(string: "https://91quanji.com/watch.jsp?v=6yo27nn31g08")),
            coverURL: XCTUnwrap(URL(string: "https://pics.mugua01.cfd/cover.jpg")),
            coverAspectRatio: 16.0 / 9.0,
            durationText: ""
        )
        let record = QuanjiFavoritesBridge.record(from: item)
        XCTAssertEqual(FavoriteSource.source(for: record), .quanji)
        XCTAssertEqual(QuanjiFavoritesBridge.item(from: record)?.id, "6yo27nn31g08")
        let lookalike = FavoriteRecord(
            id: "quanji:x", sourceID: "quanji", title: "x", rawTitle: "x", subtitle: "",
            detailURL: "https://91quanji.com.evil.example/watch.jsp?v=x",
            coverURL: nil, imageCount: 0, pageCount: 1
        )
        XCTAssertNil(QuanjiFavoritesBridge.item(from: lookalike))
    }

    private func xor80(_ text: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(text.utf16.count)
        for unit in text.utf16 {
            encoded.append(Character(UnicodeScalar(UInt32(unit ^ 128))!))
        }
        return encoded
    }
}
