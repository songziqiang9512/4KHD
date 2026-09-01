@testable import _KHD
import XCTest

@MainActor
final class DownloadStoreTests: XCTestCase {
    // MARK: - 并行调度

    func testTwoJobsRunConcurrentlyAndThirdStaysQueued() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = AsyncGate()
        store.imageFetcher = { _, _ in
            await gate.wait()
            return Data([0x01])
        }
        let sourceA = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )
        let sourceB = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/b.html")),
            title: "图集 B"
        )
        let sourceC = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/c.html")),
            title: "图集 C"
        )

        XCTAssertEqual(store.enqueueAlbum(source: sourceA, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceB, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceC, destinationRoot: root), .enqueued)

        await waitUntil {
            store.tasks.filter { $0.status == .running }.count == 2
                && store.tasks[2].status == .queued
        }
        XCTAssertEqual(store.tasks[0].status, .running)
        XCTAssertEqual(store.tasks[1].status, .running)
        XCTAssertEqual(store.tasks[2].status, .queued)

        await gate.open()
        await waitUntil {
            store.tasks.allSatisfy { $0.status.isTerminal }
        }
        XCTAssertEqual(store.tasks.map(\.status), [.completed, .completed, .completed])
        XCTAssertEqual(store.tasks[0].completedCount, 1)
        XCTAssertEqual(store.tasks[1].completedCount, 1)
        XCTAssertEqual(store.tasks[2].completedCount, 1)
        XCTAssertEqual(store.tasks[0].totalCount, store.tasks[0].completedCount + store.tasks[0].failedCount)
        XCTAssertEqual(store.tasks[0].downloadedBytes, 1)
        XCTAssertEqual(store.tasks[0].totalBytes, 1)
        XCTAssertEqual(store.tasks[0].bytesPerSecond, 0)
        XCTAssertGreaterThan(store.tasks[0].averageBytesPerSecond, 0)
    }

    func testVideoTaskSharesAlbumQueueAndPublishesProgressBeforeCompleting() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let albumGate = AsyncGate()
        store.imageFetcher = { _, _ in
            await albumGate.wait()
            return Data([0x01])
        }
        let albumSource = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )

        let videoGate = AsyncGate()
        let videoProbe = SingleFileTransferProbe()
        let videoDetailURL = try XCTUnwrap(URL(string: "https://xx.knit.bid/article/123/"))
        let videoSourceURL = try XCTUnwrap(URL(string: "https://media.knit.bid/123/master.m3u8"))
        let videoDestinationURL = root.appendingPathComponent("影片 A.mp4")
        let videoSource = SingleFileDownloadSource(
            detailURL: videoDetailURL,
            sourceURL: videoSourceURL,
            title: "影片 A",
            sourceTitle: "爱妹子",
            perform: { destinationURL, emit in
                await videoProbe.markStarted()
                emit(
                    SingleFileDownloadProgress(
                        fractionCompleted: 0.4,
                        statusText: "正在封装 MP4",
                        downloadedBytes: 400,
                        totalBytes: 1000,
                        bytesPerSecond: 80,
                        averageBytesPerSecond: 60
                    )
                )
                await videoGate.wait()
                try Task.checkCancellation()
                try Data([0x00, 0x01, 0x02]).write(to: destinationURL, options: .atomic)
            }
        )

        XCTAssertEqual(store.enqueueAlbum(source: albumSource, destinationRoot: root), .enqueued)
        XCTAssertEqual(
            store.enqueueFile(source: videoSource, destinationURL: videoDestinationURL),
            .enqueued
        )

        await waitUntil {
            store.tasks.count == 2
                && store.tasks[0].status == .running
                && store.tasks[1].status == .running
                && store.tasks[1].progressFraction == 0.4
        }
        let videoStartedWhileAlbumRunning = await videoProbe.hasStarted()
        XCTAssertTrue(videoStartedWhileAlbumRunning)
        XCTAssertEqual(store.tasks.map(\.kind), [.album, .video])
        XCTAssertEqual(store.tasks[1].destinationURL, videoDestinationURL)
        XCTAssertEqual(store.tasks[1].sourceTitle, "爱妹子")
        XCTAssertTrue(store.hasActiveVideoDownload)

        await albumGate.open()
        await waitUntil {
            store.tasks[1].status == .running
                && store.tasks[1].progressFraction == 0.4
                && store.tasks[1].progressText == "正在封装 MP4"
        }
        let videoStarted = await videoProbe.hasStarted()
        XCTAssertTrue(videoStarted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: videoDestinationURL.path))
        XCTAssertEqual(store.tasks[1].downloadedBytes, 400)
        XCTAssertEqual(store.tasks[1].totalBytes, 1000)
        XCTAssertEqual(store.tasks[1].bytesPerSecond, 80)
        XCTAssertEqual(store.tasks[1].averageBytesPerSecond, 60)

        await videoGate.open()
        await waitUntil { store.tasks[1].status == .completed }

        let videoTask = store.tasks[1]
        XCTAssertEqual(videoTask.kind, .video)
        XCTAssertEqual(videoTask.progressFraction, 1)
        XCTAssertEqual(videoTask.progressText, "MP4 已保存")
        XCTAssertEqual(videoTask.downloadedBytes, 3)
        XCTAssertEqual(videoTask.totalBytes, 3)
        XCTAssertEqual(videoTask.bytesPerSecond, 0)
        XCTAssertEqual(videoTask.averageBytesPerSecond, 60)
        XCTAssertNotNil(videoTask.startedAt)
        XCTAssertNotNil(videoTask.finishedAt)
        XCTAssertFalse(store.hasActiveVideoDownload)
        XCTAssertEqual(try Data(contentsOf: videoDestinationURL), Data([0x00, 0x01, 0x02]))
    }

    func testCancellingRunningVideoAdvancesSharedQueue() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstProbe = SingleFileTransferProbe()
        let firstDestinationURL = root.appendingPathComponent("影片 A.mp4")
        let firstSource = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/123/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/123/master.m3u8")),
            title: "影片 A",
            sourceTitle: "爱妹子",
            perform: { _, emit in
                await firstProbe.markStarted()
                emit(SingleFileDownloadProgress(fractionCompleted: 0.25, statusText: "下载分片 1 / 4"))
                while true {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        )
        let secondDestinationURL = root.appendingPathComponent("影片 B.mp4")
        let secondSource = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/456/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/456/master.m3u8")),
            title: "影片 B",
            sourceTitle: "爱妹子",
            perform: { destinationURL, _ in
                try Task.checkCancellation()
                try Data([0x03, 0x04]).write(to: destinationURL, options: .atomic)
            }
        )

        XCTAssertEqual(
            store.enqueueFile(source: firstSource, destinationURL: firstDestinationURL),
            .enqueued
        )
        XCTAssertEqual(
            store.enqueueFile(source: secondSource, destinationURL: secondDestinationURL),
            .enqueued
        )
        await waitUntil {
            store.tasks.count == 2
                && store.tasks[0].status == .running
                && store.tasks[0].progressFraction == 0.25
        }
        let firstVideoStarted = await firstProbe.hasStarted()
        XCTAssertTrue(firstVideoStarted)
        XCTAssertTrue(store.tasks[1].status == .running || store.tasks[1].status == .completed)

        store.cancelTask(id: store.tasks[0].id)
        await waitUntil {
            store.tasks[0].status == .cancelled
                && store.tasks[1].status == .completed
        }

        XCTAssertEqual(store.tasks[0].progressText, "已取消")
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstDestinationURL.path))
        XCTAssertEqual(store.tasks[1].progressFraction, 1)
        XCTAssertEqual(try Data(contentsOf: secondDestinationURL), Data([0x03, 0x04]))
        XCTAssertFalse(store.hasActiveVideoDownload)
    }

    func testActiveSingleFileDestinationIsReservedAndReleasedAfterCancellation() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let destinationURL = root.appendingPathComponent("共享目标.mp4")
        let equivalentDestinationURL = root
            .appendingPathComponent("unused", isDirectory: true)
            .appendingPathComponent("..", isDirectory: true)
            .appendingPathComponent("共享目标.mp4")
        let firstSource = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/123/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/123/master.m3u8")),
            title: "影片 A",
            sourceTitle: "爱妹子",
            perform: { _, _ in
                while true {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        )
        let secondSource = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/456/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/456/master.m3u8")),
            title: "影片 B",
            sourceTitle: "爱妹子",
            perform: { targetURL, _ in
                try Data([0x05]).write(to: targetURL, options: .atomic)
            }
        )

        XCTAssertEqual(store.enqueueFile(source: firstSource, destinationURL: destinationURL), .enqueued)
        await waitUntil { store.tasks.first?.status == .running }
        XCTAssertEqual(
            store.enqueueFile(source: secondSource, destinationURL: equivalentDestinationURL),
            .destinationInUse
        )
        XCTAssertEqual(store.tasks.count, 1)

        store.cancelTask(id: store.tasks[0].id)
        await waitUntil { store.tasks[0].status == .cancelled }
        XCTAssertEqual(
            store.enqueueFile(source: secondSource, destinationURL: destinationURL),
            .enqueued
        )
        await waitUntil { store.tasks[1].status == .completed }
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data([0x05]))
    }

    func testCancellingQueuedSingleFileReleasesDestinationReservation() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let albumGate = AsyncGate()
        store.imageFetcher = { _, _ in
            await albumGate.wait()
            return Data([0x01])
        }
        let albumSource = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )
        let albumSourceB = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/b.html")),
            title: "图集 B"
        )
        let destinationURL = root.appendingPathComponent("排队目标.mp4")
        let queuedSource = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/123/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/123/master.m3u8")),
            title: "影片 A",
            sourceTitle: "爱妹子",
            perform: { _, _ in }
        )
        let replacementSource = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/456/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/456/master.m3u8")),
            title: "影片 B",
            sourceTitle: "爱妹子",
            perform: { _, _ in }
        )

        XCTAssertEqual(store.enqueueAlbum(source: albumSource, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: albumSourceB, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueFile(source: queuedSource, destinationURL: destinationURL), .enqueued)
        await waitUntil { store.tasks.count == 3 && store.tasks[2].status == .queued }

        store.cancelTask(id: store.tasks[2].id)
        XCTAssertEqual(store.tasks[2].status, .cancelled)
        XCTAssertEqual(
            store.enqueueFile(source: replacementSource, destinationURL: destinationURL),
            .enqueued
        )

        await albumGate.open()
        await waitUntil { store.tasks.allSatisfy { $0.status.isTerminal } }
    }

    // MARK: - 同 detailURL 去重

    func testDuplicateDetailURLIsRejected() async throws {
        let store = DownloadStore()
        store.imageFetcher = { _, _ in Data([0x01]) }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let detail = try XCTUnwrap(URL(string: "https://www.4khd.com/a.html"))
        let source = makeStoreSource(detailURL: detail, title: "图集 A")
        let duplicate = makeStoreSource(detailURL: detail, title: "图集 A")

        XCTAssertEqual(store.enqueueAlbum(source: source, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: duplicate, destinationRoot: root), .duplicate)
        XCTAssertEqual(store.tasks.count, 1)

        // 完成后同 URL 可以再次入队。
        await waitUntil { store.tasks.first?.status.isTerminal == true }
        XCTAssertEqual(store.enqueueAlbum(source: duplicate, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.tasks.count, 2)
    }

    // MARK: - 同名图集目录不冲突

    func testSameTitledAlbumsGetSeparateFolders() async throws {
        let store = DownloadStore()
        let gate = AsyncGate()
        store.imageFetcher = { _, _ in
            await gate.wait()
            return Data([0x01])
        }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceA = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "同名图集"
        )
        let sourceB = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/b.html")),
            title: "同名图集"
        )

        XCTAssertEqual(store.enqueueAlbum(source: sourceA, destinationRoot: root), .enqueued)
        // 任务 A 运行中(目录已创建但为空),同名任务 B 必须拿到独立目录。
        await waitUntil { store.tasks.first?.status == .running }
        XCTAssertEqual(store.enqueueAlbum(source: sourceB, destinationRoot: root), .enqueued)

        let folderA = store.tasks[0].destinationFolderURL
        let folderB = store.tasks[1].destinationFolderURL
        XCTAssertNotEqual(folderA.path, folderB.path)
        XCTAssertEqual(folderA.lastPathComponent, "同名图集")
        XCTAssertEqual(folderB.lastPathComponent, "同名图集 (2)")

        await gate.open()
        await waitUntil { store.tasks.allSatisfy { $0.status.isTerminal } }
        // 两个目录各有一张图,互不覆盖。
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folderA.path).count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folderB.path).count, 1)
    }

    // MARK: - queued 取消

    func testCancelQueuedTask() async throws {
        let store = DownloadStore()
        let gate = AsyncGate()
        store.imageFetcher = { _, _ in
            await gate.wait()
            return Data([0x01])
        }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceA = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )
        let sourceB = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/b.html")),
            title: "图集 B"
        )
        let sourceC = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/c.html")),
            title: "图集 C"
        )
        XCTAssertEqual(store.enqueueAlbum(source: sourceA, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceB, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceC, destinationRoot: root), .enqueued)
        await waitUntil {
            store.tasks.filter { $0.status == .running }.count == 2
                && store.tasks[2].status == .queued
        }

        store.cancelTask(id: store.tasks[2].id)
        XCTAssertEqual(store.tasks[2].status, .cancelled)

        await gate.open()
        await waitUntil { store.tasks[0].status.isTerminal && store.tasks[1].status.isTerminal }
        XCTAssertEqual(store.tasks[0].status, .completed)
        XCTAssertEqual(store.tasks[1].status, .completed)
        XCTAssertEqual(store.tasks[2].status, .cancelled)
    }

    // MARK: - running 取消,已下载文件保留

    func testCancelRunningTaskKeepsPartialFiles() async throws {
        let store = DownloadStore()
        let counter = FetchCallCounter()
        store.imageFetcher = { _, _ in
            let n = await counter.next()
            if n <= 2 {
                return Data([0x01])
            }
            // 第 3 张起挂起,直到任务取消。
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            return nil
        }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A",
            imageCount: 4
        )
        XCTAssertEqual(store.enqueueAlbum(source: source, destinationRoot: root), .enqueued)
        await waitUntil {
            store.tasks.first.map { $0.status == .running && $0.completedCount >= 2 } ?? false
        }

        let destinationFolder = store.tasks[0].destinationFolderURL
        store.cancelTask(id: store.tasks[0].id)

        await waitUntil { store.tasks.first?.status == .cancelled }
        XCTAssertEqual(store.tasks[0].completedCount, 2)
        XCTAssertEqual(store.tasks[0].totalCount, 4)
        XCTAssertEqual(store.tasks[0].progressFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(store.tasks[0].downloadedBytes, 2)
        XCTAssertEqual(store.tasks[0].totalBytes, 4)
        let savedFiles = try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path)
        XCTAssertEqual(savedFiles.count, 2)
    }

    // MARK: - 全部失败 → failed，目录保留

    func testAllFailedTaskMarksFailedAndKeepsTaskFolder() async throws {
        let store = DownloadStore()
        store.imageFetcher = { _, _ in nil }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )
        XCTAssertEqual(store.enqueueAlbum(source: source, destinationRoot: root), .enqueued)
        let destinationFolder = store.tasks[0].destinationFolderURL

        await waitUntil { store.tasks.first?.status == .failed }
        XCTAssertEqual(store.tasks[0].status, .failed)
        XCTAssertEqual(store.tasks[0].completedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationFolder.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path).isEmpty)
    }

    func testRetryFailedAlbumTaskSucceedsOnSecondAttempt() async throws {
        let store = DownloadStore()
        let counter = FetchCallCounter()
        store.imageFetcher = { _, _ in
            let n = await counter.next()
            // Orchestrator retries a failed fetch once, so the first attempt
            // consumes two nils before the user-visible retry can succeed.
            if n <= 2 { return nil }
            return Data([0x01])
        }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )
        XCTAssertEqual(store.enqueueAlbum(source: source, destinationRoot: root), .enqueued)
        await waitUntil { store.tasks.first?.status == .failed }
        XCTAssertEqual(store.tasks[0].completedCount, 0)

        store.retryTask(id: store.tasks[0].id)
        await waitUntil { store.tasks.first?.status == .completed }
        XCTAssertEqual(store.tasks[0].completedCount, 1)
        XCTAssertEqual(store.tasks[0].progressFraction, 1)
    }

    func testRetryCancelledVideoTaskWritesDestination() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destinationURL = root.appendingPathComponent("影片 A.mp4")
        let shouldHang = HangSwitch()
        let source = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/123/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/123/master.m3u8")),
            title: "影片 A",
            sourceTitle: "爱妹子",
            perform: { targetURL, _ in
                if await shouldHang.isOn() {
                    while true {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                }
                try Data([0x09]).write(to: targetURL, options: .atomic)
            }
        )
        XCTAssertEqual(store.enqueueFile(source: source, destinationURL: destinationURL), .enqueued)
        await waitUntil { store.tasks.first?.status == .running }
        store.cancelTask(id: store.tasks[0].id)
        await waitUntil { store.tasks.first?.status == .cancelled }
        await shouldHang.turnOff()
        store.retryTask(id: store.tasks[0].id)
        await waitUntil { store.tasks.first?.status == .completed }
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data([0x09]))
    }

    func testPauseRunningVideoThenResumeWritesDestination() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destinationURL = root.appendingPathComponent("影片 A.mp4")
        let shouldHang = HangSwitch()
        let source = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/123/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/123/master.m3u8")),
            title: "影片 A",
            sourceTitle: "爱妹子",
            perform: { targetURL, emit in
                emit(SingleFileDownloadProgress(fractionCompleted: 0.3, statusText: "下载分片 1 / 4"))
                if await shouldHang.isOn() {
                    while true {
                        try await Task.sleep(nanoseconds: 10_000_000)
                    }
                }
                try Data([0x0A]).write(to: targetURL, options: .atomic)
            }
        )
        XCTAssertEqual(store.enqueueFile(source: source, destinationURL: destinationURL), .enqueued)
        await waitUntil {
            store.tasks.first?.status == .running
                && store.tasks.first?.progressFraction == 0.3
        }
        store.pauseTask(id: store.tasks[0].id)
        await waitUntil { store.tasks.first?.status == .paused }
        XCTAssertEqual(store.tasks[0].progressFraction, 0.3, accuracy: 0.001)
        XCTAssertTrue(store.hasActiveVideoDownload)
        XCTAssertEqual(
            store.enqueueFile(source: source, destinationURL: destinationURL),
            .duplicate
        )

        await shouldHang.turnOff()
        store.retryTask(id: store.tasks[0].id)
        await waitUntil { store.tasks.first?.status == .completed }
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data([0x0A]))
        XCTAssertFalse(store.hasActiveVideoDownload)
    }

    func testAllFailedTaskNeverUsesOrDeletesExistingEmptyFolder() async throws {
        let store = DownloadStore()
        store.imageFetcher = { _, _ in nil }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let existing = root.appendingPathComponent("图集 A", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let source = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )

        XCTAssertEqual(store.enqueueAlbum(source: source, destinationRoot: root), .enqueued)
        XCTAssertNotEqual(store.tasks[0].destinationFolderURL, existing)
        await waitUntil { store.tasks.first?.status == .failed }

        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
    }

    // MARK: - clearFinishedTasks

    func testClearFinishedTasksRemovesTerminalOnly() async throws {
        let store = DownloadStore()
        let gate = AsyncGate()
        store.imageFetcher = { _, _ in
            await gate.wait()
            return Data([0x01])
        }
        let root = makeStoreTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceA = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "图集 A"
        )
        let sourceB = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/b.html")),
            title: "图集 B"
        )
        let sourceC = try makeStoreSource(
            detailURL: XCTUnwrap(URL(string: "https://www.4khd.com/c.html")),
            title: "图集 C"
        )
        XCTAssertEqual(store.enqueueAlbum(source: sourceA, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceB, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceC, destinationRoot: root), .enqueued)
        await waitUntil {
            store.tasks.filter { $0.status == .running }.count == 2
                && store.tasks[2].status == .queued
        }

        // 取消 queued 的 C → 终态，但尚未成功；清除已完成不得动它，也不得动仍在下载的 A/B。
        store.cancelTask(id: store.tasks[2].id)
        XCTAssertEqual(store.tasks[2].status, .cancelled)
        store.clearFinishedTasks()
        XCTAssertEqual(store.tasks.count, 3)
        XCTAssertEqual(store.tasks[0].status, .running)
        XCTAssertEqual(store.tasks[1].status, .running)
        XCTAssertEqual(store.tasks[2].status, .cancelled)

        await gate.open()
        await waitUntil {
            store.tasks[0].status == .completed
                && store.tasks[1].status == .completed
                && store.tasks[2].status == .cancelled
        }
        store.clearFinishedTasks()
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks[0].status, .cancelled)
        XCTAssertEqual(store.tasks[0].title, "图集 C")
    }

    func testRemoveTaskDropsCancelledVideoFromList() async throws {
        let store = DownloadStore()
        let root = makeStoreTempFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destinationURL = root.appendingPathComponent("影片 A.mp4")
        let source = try SingleFileDownloadSource(
            detailURL: XCTUnwrap(URL(string: "https://xx.knit.bid/article/123/")),
            sourceURL: XCTUnwrap(URL(string: "https://media.knit.bid/123/master.m3u8")),
            title: "影片 A",
            sourceTitle: "爱妹子",
            perform: { _, _ in
                while true {
                    try await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        )
        XCTAssertEqual(store.enqueueFile(source: source, destinationURL: destinationURL), .enqueued)
        await waitUntil { store.tasks.first?.status == .running }
        store.cancelTask(id: store.tasks[0].id)
        await waitUntil { store.tasks.first?.status == .cancelled }
        XCTAssertEqual(store.tasks.count, 1)
        store.removeTask(id: store.tasks[0].id)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    // MARK: - 等待辅助

    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }
}

// MARK: - Helpers(自由函数,供 @Sendable 闭包调用)

private func makeStoreTempFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("4KHDDownloadStoreTests-\(UUID().uuidString)", isDirectory: true)
}

private func makeStoreSource(
    detailURL: URL,
    title: String,
    imageCount: Int = 1
) -> AlbumDownloadSource {
    let pageURLs = (1 ... imageCount).map { index in
        index == 1 ? detailURL : URL(string: "\(detailURL.absoluteString)/\(index)")!
    }
    return AlbumDownloadSource(
        detailURL: detailURL,
        title: title,
        estimatedImageCount: imageCount,
        initialPageURLs: [detailURL],
        resolvePage: { pageURL in
            AlbumResolvedPage(
                pageURL: pageURL,
                imageURLs: [URL(string: "https://img.4khd.com/\(pageURL.hashValue).jpg")!],
                pageURLs: pageURLs
            )
        },
        configureImageRequest: { _ in }
    )
}

// MARK: - 测试替身

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor HangSwitch {
    private var on = true

    func isOn() -> Bool {
        on
    }

    func turnOff() {
        on = false
    }
}

private actor FetchCallCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

private actor SingleFileTransferProbe {
    private var started = false

    func markStarted() {
        started = true
    }

    func hasStarted() -> Bool {
        started
    }
}
