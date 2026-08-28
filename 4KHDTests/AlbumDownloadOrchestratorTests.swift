@testable import _KHD
import XCTest

/// App target 在 SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 下编译,AlbumDownloadEvent/
/// AlbumDownloadSummary 等结构体的成员是 MainActor 隔离的;测试方法整体标 @MainActor,
/// 助手函数移出类,避免 @Sendable 闭包捕获 self。
@MainActor
final class AlbumDownloadOrchestratorTests: XCTestCase {
    // MARK: - 并发上限

    func testImageFetchesRespectConcurrencyLimit() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = FetchConcurrencyRecorder()
        let byteRecorder = WrittenByteRecorder()
        let detailURL = try XCTUnwrap(URL(string: "https://www.4khd.com/test.html"))
        let source = makeOrchestratorSource(detailURL: detailURL) { pageURL in
            makeOrchestratorPage(pageURL, imageCount: 6, pageURLs: [pageURL])
        }

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            maxConcurrentImages: 3,
            registry: ImageTaskRegistry(),
            emit: { event in byteRecorder.record(event) },
            fetcher: { _, _ in
                await recorder.begin()
                try? await Task.sleep(nanoseconds: 30_000_000)
                await recorder.end()
                return Data(repeating: 0x01, count: 4)
            }
        )

        XCTAssertEqual(summary.completedCount, 6)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(summary.downloadedBytes, 24)
        XCTAssertEqual(byteRecorder.writtenBytes.sorted(), Array(repeating: 4, count: 6))
        let maxActive = await recorder.maxActive
        XCTAssertLessThanOrEqual(maxActive, 3)
        XCTAssertGreaterThan(maxActive, 1)
    }

    // MARK: - 单张失败重试一次

    func testSingleImageFailureRetriesOnce() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let recorder = FetchAttemptRecorder()
        let detailURL = try XCTUnwrap(URL(string: "https://www.4khd.com/test.html"))
        let source = makeOrchestratorSource(detailURL: detailURL) { pageURL in
            makeOrchestratorPage(pageURL, imageCount: 3, pageURLs: [pageURL])
        }
        let flakyURL = try XCTUnwrap(URL(string: "https://img.4khd.com/\(detailURL.hashValue)-2.jpg"))

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            registry: ImageTaskRegistry(),
            emit: { _ in },
            fetcher: { url, _ in
                let attempt = await recorder.recordAttempt(for: url)
                if attempt == 1, url == flakyURL {
                    return nil
                }
                return Data([0x01])
            }
        )

        XCTAssertEqual(summary.completedCount, 3)
        XCTAssertEqual(summary.failedCount, 0)
        let flakyAttempts = await recorder.attempts(for: flakyURL)
        XCTAssertEqual(flakyAttempts, 2)
        let normalAttempts = try await recorder.attempts(
            for: XCTUnwrap(URL(string: "https://img.4khd.com/\(detailURL.hashValue)-1.jpg"))
        )
        XCTAssertEqual(normalAttempts, 1)
    }

    // MARK: - 页失败标记并继续

    func testFailedPageIsMarkedAndRemainingPagesContinue() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/a.html"))
        let page2 = try XCTUnwrap(URL(string: "https://www.4khd.com/a.html/2"))
        let page3 = try XCTUnwrap(URL(string: "https://www.4khd.com/a.html/3"))
        let source = makeOrchestratorSource(detailURL: page1) { pageURL in
            if pageURL == page2 {
                throw URLError(.cannotParseResponse)
            }
            return makeOrchestratorPage(pageURL, imageCount: 1, pageURLs: [page1, page2, page3])
        }

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            registry: ImageTaskRegistry(),
            emit: { _ in },
            fetcher: { _, _ in Data([0x01]) }
        )

        XCTAssertEqual(summary.failedPageCount, 1)
        XCTAssertEqual(summary.completedCount, 2)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertFalse(summary.cancelled)
    }

    // MARK: - 取消提前返回

    func testCancellationStopsEarlyAndReportsCancelled() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let detailURL = try XCTUnwrap(URL(string: "https://www.4khd.com/a.html"))
        let source = makeOrchestratorSource(detailURL: detailURL) { pageURL in
            try Task.checkCancellation()
            try? await Task.sleep(nanoseconds: 50_000_000)
            try Task.checkCancellation()
            return makeOrchestratorPage(pageURL, imageCount: 3, pageURLs: [pageURL])
        }

        let task = Task {
            await AlbumDownloadOrchestrator.run(
                source: source,
                destinationFolder: folder,
                registry: ImageTaskRegistry(),
                emit: { _ in },
                fetcher: { _, _ in
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    return Data([0x01])
                }
            )
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let summary = await task.value

        XCTAssertTrue(summary.cancelled)
        XCTAssertEqual(summary.completedCount, 0)
    }

    // MARK: - 目录创建失败

    func testFolderCreationFailureReportsError() async throws {
        // 父路径是文件,createDirectory 必然失败。
        let root = makeOrchestratorTempFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blocker = root.appendingPathComponent("blocker")
        try Data([0x01]).write(to: blocker)
        let destinationFolder = blocker.appendingPathComponent("album", isDirectory: true)
        let detailURL = try XCTUnwrap(URL(string: "https://www.4khd.com/test.html"))
        let source = makeOrchestratorSource(detailURL: detailURL) { pageURL in
            makeOrchestratorPage(pageURL, imageCount: 1, pageURLs: [pageURL])
        }

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: destinationFolder,
            registry: ImageTaskRegistry(),
            emit: { _ in }
        )

        XCTAssertNotNil(summary.folderCreationError)
        XCTAssertEqual(summary.completedCount, 0)
    }

    // MARK: - 首页解析后替换 worklist

    func testFirstPageResolutionReplacesWorklist() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/b.html"))
        let page2 = try XCTUnwrap(URL(string: "https://www.4khd.com/b.html/2"))
        let recorder = ResolvedURLRecorder()
        let source = makeOrchestratorSource(detailURL: page1) { pageURL in
            recorder.urls.append(pageURL)
            return makeOrchestratorPage(pageURL, imageCount: 1, pageURLs: [page1, page2])
        }

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            registry: ImageTaskRegistry(),
            emit: { _ in },
            fetcher: { _, _ in Data([0x01]) }
        )

        XCTAssertEqual(summary.completedCount, 2)
        // 初始 worklist 只有首页,解析成功后应继续解析第 2 页。
        XCTAssertEqual(recorder.urls, [page1, page2])
    }

    // MARK: - 错页开头不重不漏

    func testOffPageStartDoesNotSkipOrDuplicatePages() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/c.html"))
        let page2 = try XCTUnwrap(URL(string: "https://www.4khd.com/c.html/2"))
        let page3 = try XCTUnwrap(URL(string: "https://www.4khd.com/c.html/3"))
        let recorder = ResolvedURLRecorder()
        // 入口 URL 是第 2 页(例如收藏的 detailURL 带页号后缀)。
        let source = AlbumDownloadSource(
            detailURL: page2,
            title: "测试图集",
            estimatedImageCount: 3,
            initialPageURLs: [page2],
            resolvePage: { pageURL in
                recorder.urls.append(pageURL)
                return makeOrchestratorPage(pageURL, imageCount: 1, pageURLs: [page1, page2, page3])
            },
            configureImageRequest: { _ in }
        )

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            registry: ImageTaskRegistry(),
            emit: { _ in },
            fetcher: { _, _ in Data([0x01]) }
        )

        // 第 1 页不能被漏掉,已解析的第 2 页不能被重复下载。
        XCTAssertEqual(recorder.urls, [page2, page1, page3])
        XCTAssertEqual(summary.completedCount, 3)
        XCTAssertEqual(summary.failedPageCount, 0)
    }

    // MARK: - 跨页重复图片只下载一次

    func testDuplicateImagesAcrossPagesDownloadedOnce() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/d.html"))
        let page2 = try XCTUnwrap(URL(string: "https://www.4khd.com/d.html/2"))
        let imageA = try XCTUnwrap(URL(string: "https://img.4khd.com/a.jpg"))
        let imageB = try XCTUnwrap(URL(string: "https://img.4khd.com/b.jpg"))
        let imageC = try XCTUnwrap(URL(string: "https://img.4khd.com/c.jpg"))
        let source = AlbumDownloadSource(
            detailURL: page1,
            title: "测试图集",
            estimatedImageCount: 4,
            initialPageURLs: [page1],
            resolvePage: { pageURL in
                if pageURL == page1 {
                    return AlbumResolvedPage(pageURL: page1, imageURLs: [imageA, imageB], pageURLs: [page1, page2])
                }
                // 分页边界重复最后一张(b)。
                return AlbumResolvedPage(pageURL: page2, imageURLs: [imageB, imageC], pageURLs: [page1, page2])
            },
            configureImageRequest: { _ in }
        )

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            registry: ImageTaskRegistry(),
            emit: { _ in },
            fetcher: { _, _ in Data([0x01]) }
        )

        XCTAssertEqual(summary.completedCount, 3)
        let savedNames = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(savedNames.count, 3)
    }

    // MARK: - 页解析失败重试一次

    func testPageResolveFailureRetriesOnce() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let detailURL = try XCTUnwrap(URL(string: "https://www.4khd.com/e.html"))
        let recorder = ResolveAttemptRecorder()
        let source = makeOrchestratorSource(detailURL: detailURL) { pageURL in
            let attempt = await recorder.recordAttempt(for: pageURL)
            if attempt == 1 {
                throw URLError(.notConnectedToInternet)
            }
            return makeOrchestratorPage(pageURL, imageCount: 1, pageURLs: [pageURL])
        }

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            registry: ImageTaskRegistry(),
            emit: { _ in },
            fetcher: { _, _ in Data([0x01]) }
        )

        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.failedPageCount, 0)
        let attempts = await recorder.attempts(for: detailURL)
        XCTAssertEqual(attempts, 2)
    }

    // MARK: - 替换清单后的失败页不被反复解析

    func testFailedPageAfterWorklistReplacementNotRetriedEndlessly() async throws {
        let folder = makeOrchestratorTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let page1 = try XCTUnwrap(URL(string: "https://www.4khd.com/f.html"))
        let page2 = try XCTUnwrap(URL(string: "https://www.4khd.com/f.html/2"))
        let page3 = try XCTUnwrap(URL(string: "https://www.4khd.com/f.html/3"))
        let recorder = ResolveAttemptRecorder()
        // 入口是第 2 页:替换 worklist 后重新扫描 [p1, p2, p3];p1 持续失败。
        let source = AlbumDownloadSource(
            detailURL: page2,
            title: "测试图集",
            estimatedImageCount: 3,
            initialPageURLs: [page2],
            resolvePage: { pageURL in
                _ = await recorder.recordAttempt(for: pageURL)
                if pageURL == page1 {
                    throw URLError(.cannotParseResponse)
                }
                return makeOrchestratorPage(pageURL, imageCount: 1, pageURLs: [page1, page2, page3])
            },
            configureImageRequest: { _ in }
        )

        let summary = await AlbumDownloadOrchestrator.run(
            source: source,
            destinationFolder: folder,
            registry: ImageTaskRegistry(),
            emit: { _ in },
            fetcher: { _, _ in Data([0x01]) }
        )

        XCTAssertEqual(summary.failedPageCount, 1)
        XCTAssertEqual(summary.completedCount, 2)
        // 失败页只有"首次 + 重试一次"两次尝试,不会被重新扫描反复解析。
        let page1Attempts = await recorder.attempts(for: page1)
        XCTAssertEqual(page1Attempts, 2)
        let page2Attempts = await recorder.attempts(for: page2)
        XCTAssertEqual(page2Attempts, 1)
        let page3Attempts = await recorder.attempts(for: page3)
        XCTAssertEqual(page3Attempts, 1)
    }
}

// MARK: - Helpers(自由函数,供 @Sendable 闭包调用)

private func makeOrchestratorTempFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("4KHDOrchestratorTests-\(UUID().uuidString)", isDirectory: true)
}

private func makeOrchestratorSource(
    detailURL: URL,
    resolvePage: @escaping @Sendable @MainActor (URL) async throws -> AlbumResolvedPage
) -> AlbumDownloadSource {
    AlbumDownloadSource(
        detailURL: detailURL,
        title: "测试图集",
        estimatedImageCount: 0,
        initialPageURLs: [detailURL],
        resolvePage: resolvePage,
        configureImageRequest: { _ in }
    )
}

private func makeOrchestratorPage(_ pageURL: URL, imageCount: Int, pageURLs: [URL]) -> AlbumResolvedPage {
    // 图片 URL 带页标识,避免跨页去重误杀不同页的同序号图片。
    let imageURLs = (1 ... imageCount).map { URL(string: "https://img.4khd.com/\(pageURL.hashValue)-\($0).jpg")! }
    return AlbumResolvedPage(pageURL: pageURL, imageURLs: imageURLs, pageURLs: pageURLs)
}

// MARK: - 测试替身

private actor FetchConcurrencyRecorder {
    private(set) var maxActive = 0
    private var active = 0

    func begin() {
        active += 1
        maxActive = max(maxActive, active)
    }

    func end() {
        active -= 1
    }
}

private final class WrittenByteRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedBytes: [Int64] = []

    func record(_ event: AlbumDownloadEvent) {
        guard case .imageSucceeded(_, _, let bytesWritten) = event else { return }
        lock.lock()
        storedBytes.append(bytesWritten)
        lock.unlock()
    }

    var writtenBytes: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return storedBytes
    }
}

private actor ResolveAttemptRecorder {
    private var attemptsByURL: [String: Int] = [:]

    func recordAttempt(for url: URL) -> Int {
        let key = url.absoluteString
        let count = (attemptsByURL[key] ?? 0) + 1
        attemptsByURL[key] = count
        return count
    }

    func attempts(for url: URL) -> Int {
        attemptsByURL[url.absoluteString] ?? 0
    }
}

private actor FetchAttemptRecorder {
    private var attemptsByURL: [String: Int] = [:]

    func recordAttempt(for url: URL) -> Int {
        let key = url.absoluteString
        let count = (attemptsByURL[key] ?? 0) + 1
        attemptsByURL[key] = count
        return count
    }

    func attempts(for url: URL) -> Int {
        attemptsByURL[url.absoluteString] ?? 0
    }
}

@MainActor
private final class ResolvedURLRecorder {
    var urls: [URL] = []
}
