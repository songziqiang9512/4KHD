import AppKit
import XCTest
@testable import _KHD

final class LocalLibraryBookmarkTests: XCTestCase {
    @MainActor
    func testImportedRootPersistsSecurityScopedBookmarkAndRestores() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDLocalBookmarkTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makePNGData().write(to: root.appendingPathComponent("sample.png"))
        let suiteName = "4KHDLocalBookmarkTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var firstStore: LocalLibraryStore? = LocalLibraryStore(defaults: defaults)
        await Task.yield()
        firstStore?.importRootFolder(root)
        await waitUntil { firstStore?.isScanning == false }
        XCTAssertEqual(firstStore?.roots.first?.url.standardizedFileURL, root.standardizedFileURL)

        let bookmarkData = try XCTUnwrap(defaults.data(forKey: "com.songziqiang.4khd.localRootBookmarks.v3"))
        let records = try JSONDecoder().decode([LocalLibraryRootBookmarkRecord].self, from: bookmarkData)
        XCTAssertEqual(records.map(\.path), [root.path])
        XCTAssertFalse(try XCTUnwrap(records.first?.bookmarkData).isEmpty)

        firstStore = nil
        let restoredStore = LocalLibraryStore(defaults: defaults)
        await waitUntil { restoredStore.isScanning == false }
        XCTAssertEqual(restoredStore.roots.first?.url.standardizedFileURL, root.standardizedFileURL)
        XCTAssertEqual(restoredStore.roots.first?.imageCount, 1)
    }

    @MainActor
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
