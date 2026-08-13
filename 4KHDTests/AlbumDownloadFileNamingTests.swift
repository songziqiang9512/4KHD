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

    // MARK: - 转码后扩展名覆盖

    func testUniqueFileNamePreferredExtensionOverridesURL() throws {
        let folder = makeTempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        // webp URL + 转码扩展名 → 落盘 .png
        let converted = try AlbumDownloadFileNaming.uniqueFileName(
            for: XCTUnwrap(URL(string: "https://x.com/photo.webp")),
            in: folder,
            preferredExtension: "png"
        )
        XCTAssertEqual(converted.lastPathComponent, "photo.png")

        // 冲突序号同样适用
        try Data([0x01]).write(to: folder.appendingPathComponent("photo.png"))
        let convertedCollided = try AlbumDownloadFileNaming.uniqueFileName(
            for: XCTUnwrap(URL(string: "https://x.com/photo.webp")),
            in: folder,
            preferredExtension: "png"
        )
        XCTAssertEqual(convertedCollided.lastPathComponent, "photo (1).png")
    }

    // MARK: - WebP 检测与转码 fallback

    func testWebPDetectionAndNonWebPPassthrough() {
        // RIFF....WEBP 魔数
        var webp = Data("RIFF".utf8)
        webp.append(Data([0x00, 0x00, 0x00, 0x00]))
        webp.append(Data("WEBP".utf8))
        webp.append(Data([0x01, 0x02]))
        XCTAssertTrue(AlbumImageFormatConverter.isWebP(webp))

        // 假 WEBP 数据无法解码 → 原样返回,扩展名 nil
        let fallback = AlbumImageFormatConverter.convertingToPNGIfWebP(webp)
        XCTAssertEqual(fallback.data, webp)
        XCTAssertNil(fallback.extensionName)

        // JPEG 魔数 → 原样
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x02])
        XCTAssertFalse(AlbumImageFormatConverter.isWebP(jpeg))
        let passthrough = AlbumImageFormatConverter.convertingToPNGIfWebP(jpeg)
        XCTAssertEqual(passthrough.data, jpeg)
        XCTAssertNil(passthrough.extensionName)

        // 短数据不误判
        XCTAssertFalse(AlbumImageFormatConverter.isWebP(Data([0x01])))
    }

    private func makeTempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("4KHDFileNamingTests-\(UUID().uuidString)", isDirectory: true)
    }
}
