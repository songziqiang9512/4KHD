@testable import _KHD
import XCTest

final class AlbumDownloadFileNamingTests: XCTestCase {
    // MARK: - 目录名规整

    func testSanitizedFolderNameReplacesIllegalCharactersAndTrims() {
        XCTAssertEqual(
            AlbumDownloadFileNaming.sanitizedFolderName(#"a/b\c:d*e?f"g<h>i|j"#),
            "a-b-c-d-e-f-g-h-i-j"
        )
        XCTAssertEqual(AlbumDownloadFileNaming.sanitizedFolderName("  前后空白  "), "前后空白")
        XCTAssertEqual(AlbumDownloadFileNaming.sanitizedFolderName("   "), "未命名图集")
        XCTAssertEqual(
            AlbumDownloadFileNaming.sanitizedFolderName(String(repeating: "长", count: 100)).count,
            80
        )
    }

    // MARK: - 目录冲突序号

    func testUniqueDestinationFolderReusesEmptyAndSuffixesNonEmpty() throws {
        let root = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        // 空目录直接复用
        let empty = root.appendingPathComponent("图集 A", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertEqual(
            AlbumDownloadFileNaming.uniqueDestinationFolder(root: root, albumName: "图集 A").path,
            empty.path
        )

        // 非空目录 → "图集 A (2)"
        try Data([0x01]).write(to: empty.appendingPathComponent("x.jpg"))
        let suffixed = AlbumDownloadFileNaming.uniqueDestinationFolder(root: root, albumName: "图集 A")
        XCTAssertEqual(suffixed.lastPathComponent, "图集 A (2)")

        // "图集 A (2)" 已存在且非空 → "图集 A (3)"
        try FileManager.default.createDirectory(at: suffixed, withIntermediateDirectories: true)
        try Data([0x01]).write(to: suffixed.appendingPathComponent("y.jpg"))
        let nextSuffixed = AlbumDownloadFileNaming.uniqueDestinationFolder(root: root, albumName: "图集 A")
        XCTAssertEqual(nextSuffixed.lastPathComponent, "图集 A (3)")

        // 不存在则直接取规整名
        let fresh = AlbumDownloadFileNaming.uniqueDestinationFolder(root: root, albumName: "新图集")
        XCTAssertEqual(fresh.lastPathComponent, "新图集")
    }

    // MARK: - 文件名 fallback 与冲突

    func testUniqueFileNameFallbackExtensionAndCollision() throws {
        let folder = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // 无扩展名补 .jpg
        let noExtension = try AlbumDownloadFileNaming.uniqueFileName(
            for: XCTUnwrap(URL(string: "https://x.com/abc")),
            in: folder
        )
        XCTAssertEqual(noExtension.lastPathComponent, "abc.jpg")

        // 磁盘已存在 → "abc (1).jpg"
        try Data([0x01]).write(to: folder.appendingPathComponent("abc.jpg"))
        let collided = try AlbumDownloadFileNaming.uniqueFileName(
            for: XCTUnwrap(URL(string: "https://x.com/abc")),
            in: folder
        )
        XCTAssertEqual(collided.lastPathComponent, "abc (1).jpg")

        // reservedNames 排除(运行内已分配) → "def (1).jpg"
        let reserved = try AlbumDownloadFileNaming.uniqueFileName(
            for: XCTUnwrap(URL(string: "https://x.com/def.jpg")),
            in: folder,
            excluding: ["def.jpg"]
        )
        XCTAssertEqual(reserved.lastPathComponent, "def (1).jpg")
    }

    private func makeTempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDFileNamingTests-\(UUID().uuidString)", isDirectory: true)
    }
}
