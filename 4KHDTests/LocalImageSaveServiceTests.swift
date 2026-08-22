import XCTest
@testable import _KHD

final class LocalImageSaveServiceTests: XCTestCase {
    func testSavingToSourcePathLeavesSourceUntouched() throws {
        let root = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.jpg")
        let original = Data("original".utf8)
        try original.write(to: source)

        try LocalImageSaveService.save(sourceURL: source, targetURL: source)

        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testSavingThroughSymlinkToSourceLeavesSourceUntouched() throws {
        let root = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.jpg")
        let symlink = root.appendingPathComponent("alias.jpg")
        let original = Data("original".utf8)
        try original.write(to: source)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)

        try LocalImageSaveService.save(sourceURL: source, targetURL: symlink)

        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path), source.path)
    }

    func testReplacingExistingTargetKeepsSourceAndWritesNewContents() throws {
        let root = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.jpg")
        let target = root.appendingPathComponent("target.jpg")
        let original = Data("source".utf8)
        try original.write(to: source)
        try Data("old-target".utf8).write(to: target)

        try LocalImageSaveService.save(sourceURL: source, targetURL: target)

        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(try Data(contentsOf: target), original)
    }

    private func makeTempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDLocalImageSaveTests-\(UUID().uuidString)", isDirectory: true)
    }
}
