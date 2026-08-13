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
                    // 目标已存在时先移到废纸篓再复制：复制失败不会丢掉用户原有文件。
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.trashItem(at: target, resultingItemURL: nil)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: target)
                }.value
                self?.saveMessage = "已保存"
            } catch {
                self?.saveMessage = "保存失败"
            }
        }
    }
}
