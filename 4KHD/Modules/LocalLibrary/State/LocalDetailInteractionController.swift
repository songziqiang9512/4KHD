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

        do {
            if FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.copyItem(at: image.url, to: target)
            saveMessage = "已保存"
        } catch {
            saveMessage = "保存失败"
        }
    }
}
