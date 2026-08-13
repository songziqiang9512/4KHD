@testable import _KHD
import XCTest

@MainActor
final class DownloadStoreTests: XCTestCase {
    // MARK: - 串行调度

    func testTasksRunSerially() async throws {
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

        XCTAssertEqual(store.enqueueAlbum(source: sourceA, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceB, destinationRoot: root), .enqueued)

        // A 运行中,B 必须保持 queued。
        await waitUntil {
            store.tasks.first?.status == .running
        }
        XCTAssertEqual(store.tasks[0].status, .running)
        XCTAssertEqual(store.tasks[1].status, .queued)

        // 放行 A,A 完成后 B 自动开始并完成。
        await gate.open()
        await waitUntil {
            store.tasks.allSatisfy { $0.status.isTerminal }
        }
        XCTAssertEqual(store.tasks[0].status, .completed)
        XCTAssertEqual(store.tasks[1].status, .completed)
        XCTAssertEqual(store.tasks[0].completedCount, 1)
        XCTAssertEqual(store.tasks[1].completedCount, 1)
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
        let sourceA = makeStoreSource(
            detailURL: try XCTUnwrap(URL(string: "https://www.4khd.com/a.html")),
            title: "同名图集"
        )
        let sourceB = makeStoreSource(
            detailURL: try XCTUnwrap(URL(string: "https://www.4khd.com/b.html")),
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
        XCTAssertEqual(store.enqueueAlbum(source: sourceA, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceB, destinationRoot: root), .enqueued)
        await waitUntil { store.tasks.first?.status == .running }

        store.cancelTask(id: store.tasks[1].id)
        XCTAssertEqual(store.tasks[1].status, .cancelled)

        await gate.open()
        await waitUntil { store.tasks[0].status.isTerminal }
        XCTAssertEqual(store.tasks[0].status, .completed)
        XCTAssertEqual(store.tasks[1].status, .cancelled)
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
        let savedFiles = try FileManager.default.contentsOfDirectory(atPath: destinationFolder.path)
        XCTAssertEqual(savedFiles.count, 2)
    }

    // MARK: - 全部失败 → failed + 删空目录

    func testAllFailedTaskMarksFailedAndDeletesEmptyFolder() async throws {
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: destinationFolder.path))
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
        XCTAssertEqual(store.enqueueAlbum(source: sourceA, destinationRoot: root), .enqueued)
        XCTAssertEqual(store.enqueueAlbum(source: sourceB, destinationRoot: root), .enqueued)
        await waitUntil { store.tasks.first?.status == .running }

        // 取消 queued 的 B → 终态;A 仍在运行。
        store.cancelTask(id: store.tasks[1].id)
        XCTAssertEqual(store.tasks[1].status, .cancelled)
        store.clearFinishedTasks()
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks[0].status, .running)

        await gate.open()
        await waitUntil { store.tasks.first?.status.isTerminal == true }
        XCTAssertEqual(store.tasks.count, 1)
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

private actor FetchCallCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}
