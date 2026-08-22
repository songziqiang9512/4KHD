import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class LocalDetailInteractionController {
    var resetToken = UUID()
    var saveMessage = ""

    func resetZoom() {
        resetToken = UUID()
    }

    func save(image: LocalImageItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.image]
        panel.nameFieldStringValue = image.title
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        let sourceURL = image.url
        saveMessage = "保存中"
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    try LocalImageSaveService.save(sourceURL: sourceURL, targetURL: target)
                }.value
                self?.saveMessage = "已保存"
            } catch {
                self?.saveMessage = "保存失败"
            }
        }
    }
}

enum LocalImageSaveService {
    /// Copies an image without ever removing the source or the previous target
    /// before a complete replacement file exists.
    nonisolated static func save(
        sourceURL: URL,
        targetURL: URL,
        fileManager: FileManager = .default
    ) throws {
        if try referencesSameFile(sourceURL, targetURL, fileManager: fileManager) {
            return
        }

        let parent = targetURL.deletingLastPathComponent()
        let temporaryURL = parent.appendingPathComponent(".4khd-save-\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(targetURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        }
    }

    private nonisolated static func referencesSameFile(
        _ lhs: URL,
        _ rhs: URL,
        fileManager: FileManager
    ) throws -> Bool {
        let normalizedLHS = lhs.standardizedFileURL.resolvingSymlinksInPath()
        let normalizedRHS = rhs.standardizedFileURL.resolvingSymlinksInPath()
        if normalizedLHS == normalizedRHS {
            return true
        }
        guard fileManager.fileExists(atPath: lhs.path),
              fileManager.fileExists(atPath: rhs.path) else {
            return false
        }
        let lhsAttributes = try fileManager.attributesOfItem(atPath: lhs.path)
        let rhsAttributes = try fileManager.attributesOfItem(atPath: rhs.path)
        return lhsAttributes[.systemNumber] as? NSNumber == rhsAttributes[.systemNumber] as? NSNumber
            && lhsAttributes[.systemFileNumber] as? NSNumber == rhsAttributes[.systemFileNumber] as? NSNumber
    }
}
