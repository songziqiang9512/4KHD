import AppKit
import XCTest
@testable import _KHD

final class ImageCacheAndLocalScanTests: XCTestCase {
    @MainActor
    func testCancellingRemoteLoadHandlePreventsDelayedRetry() async {
        let retryExpectation = expectation(description: "delayed retry")
        retryExpectation.isInverted = true
        let task = RemoteImageLoadTask()
        task.scheduleRetry(after: 0.02) {
            retryExpectation.fulfill()
        }

        task.cancel()

        await fulfillment(of: [retryExpectation], timeout: 0.1)
    }

    @MainActor
    func testReusableRemoteImageViewClearsOldBitmapWhenURLChanges() throws {
        let view = RemoteImageView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let oldURL = try XCTUnwrap(URL(string: "https://example.invalid/old.jpg"))
        let newURL = try XCTUnwrap(URL(string: "https://example.invalid/new.jpg"))
        view.setImage(url: oldURL)
        view.setDisplayedImageForTesting(NSImage(size: NSSize(width: 1, height: 1)))

        view.setImage(url: newURL)

        XCTAssertNil(view.displayedImageForTesting)
        view.cancelPendingLoad()
    }

    func testPixelSizeCacheHasHardLimitAndCanRemoveRootEntries() throws {
        let root = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let cache = LocalPixelSizeCache(maxEntryCount: 3)

        for index in 0..<8 {
            let file = root.appendingPathComponent("\(index).png")
            try Data([UInt8(index)]).write(to: file)
            _ = cache.size(for: file)
        }

        XCTAssertLessThanOrEqual(cache.entryCount, 3)
        cache.removeEntries(under: root)
        XCTAssertEqual(cache.entryCount, 0)
    }

    @MainActor
    func testLocalScanSkipsPackagesAndSymbolicLinkLoops() async throws {
        let root = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makePNGData().write(to: root.appendingPathComponent("visible.png"))

        let package = root.appendingPathComponent("Ignored.photoslibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try makePNGData().write(to: package.appendingPathComponent("hidden.png"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("loop", isDirectory: true),
            withDestinationURL: root
        )

        let suiteName = "4KHDLocalScanTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LocalLibraryStore(defaults: defaults)
        store.importRootFolder(root)
        await waitUntil { !store.isScanning }

        XCTAssertEqual(store.roots.first?.imageCount, 1)
        XCTAssertEqual(store.selectedImages.map(\.title), ["visible.png"])
    }

    func testLocalThumbnailFirstWriteCanBeReadFromDiskCache() async throws {
        let root = makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.png")
        try makePNGData().write(to: source)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let version = LocalImageCache.FileVersion(
            fileSize: (attributes[.size] as? NSNumber)?.int64Value,
            modifiedAt: attributes[.modificationDate] as? Date
        )

        try await LocalImageCache.shared.clear()
        let first = await LocalImageCache.shared.image(for: source, maxPixelSize: 64, fileVersion: version)
        XCTAssertNotNil(first)
        await LocalImageCache.shared.clearMemoryOnlyForTesting()
        try FileManager.default.removeItem(at: source)
        let second = await LocalImageCache.shared.image(for: source, maxPixelSize: 64, fileVersion: version)

        XCTAssertNotNil(second)
        XCTAssertTrue(LocalImageCache.diskCacheDirectoryForTesting.path.contains("/Library/Caches/4KHD/"))
        try await LocalImageCache.shared.clear()
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition())
    }

    private func makeTemporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDImageCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makePNGData() throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.setColor(.white, atX: 0, y: 0)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
