import Foundation

enum AlbumDownloadFileNaming {
    private nonisolated static let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")

    /// 非法字符替换为 "-"、去首尾空白、截 80 字符,空结果回退「未命名图集」。
    nonisolated static func sanitizedFolderName(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { invalidCharacters.contains($0) ? "-" : String($0) }
        let trimmed = scalars.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = String(trimmed.prefix(80))
        return capped.isEmpty ? "未命名图集" : capped
    }

    /// 在 root 下为图集取目录:目录不存在直接用规整名;存在且为空则复用;
    /// 存在且非空则依次尝试 "name (2)"、"name (3)"…。
    /// reservedPaths 排除本次会话内已分配给其他任务的目录(即使尚未创建),
    /// 防止同名图集并发下载写进同一目录互相覆盖。
    nonisolated static func uniqueDestinationFolder(
        root: URL,
        albumName: String,
        excluding reservedPaths: Set<String> = []
    ) -> URL {
        let base = sanitizedFolderName(albumName)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) || reservedPaths.contains(candidate.path) {
            if !reservedPaths.contains(candidate.path), isDirectoryEmpty(candidate) {
                return candidate
            }
            candidate = root.appendingPathComponent("\(base) (\(index))", isDirectory: true)
            index += 1
        }
        return candidate
    }

    /// lastPathComponent 去碰撞:"abc.jpg" 已存在时生成 "abc (1).jpg";
    /// 无扩展名补 ".jpg";reservedNames 用于排除本次运行内已分配的名字。
    /// preferredExtension 传入时覆盖 URL 自带扩展名(如 webp 转 png 后落盘)。
    nonisolated static func uniqueFileName(
        for imageURL: URL,
        in folder: URL,
        excluding reservedNames: Set<String> = [],
        preferredExtension: String? = nil
    ) -> URL {
        let (base, ext) = splitFileName(imageURL.lastPathComponent, preferredExtension: preferredExtension)
        func isTaken(_ name: String) -> Bool {
            reservedNames.contains(name)
                || FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
        }
        var candidate = base + ext
        var index = 1
        while isTaken(candidate) {
            candidate = "\(base) (\(index))\(ext)"
            index += 1
        }
        return folder.appendingPathComponent(candidate)
    }

    private nonisolated static func isDirectoryEmpty(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return contents.isEmpty
    }

    private nonisolated static func splitFileName(
        _ rawName: String,
        preferredExtension: String?
    ) -> (base: String, ext: String) {
        let fallback: (base: String, ext: String)
        if let dotIndex = rawName.lastIndex(of: "."),
           rawName.index(after: dotIndex) != rawName.endIndex {
            let base = String(rawName[..<dotIndex])
            fallback = (base.isEmpty ? "image" : base, String(rawName[dotIndex...]))
        } else {
            fallback = (rawName, ".jpg")
        }
        guard let preferredExtension else { return fallback }
        return (fallback.base, "." + preferredExtension)
    }
}

/// 一次下载运行内的文件名分配器:磁盘存在性检查 + 运行内已分配名
/// 都在锁内完成,并发下载不会拿到同一个目标名。
final nonisolated class AlbumFileNameAllocator: @unchecked Sendable {
    private let lock = NSLock()
    private let folder: URL
    private var reservedNames = Set<String>()

    init(folder: URL) {
        self.folder = folder
    }

    func allocate(for imageURL: URL, preferredExtension: String? = nil) -> URL {
        lock.lock()
        defer { lock.unlock() }
        let candidate = AlbumDownloadFileNaming.uniqueFileName(
            for: imageURL,
            in: folder,
            excluding: reservedNames,
            preferredExtension: preferredExtension
        )
        reservedNames.insert(candidate.lastPathComponent)
        return candidate
    }
}
