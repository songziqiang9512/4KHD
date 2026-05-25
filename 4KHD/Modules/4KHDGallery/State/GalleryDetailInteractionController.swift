import AppKit
import Foundation
import Nuke
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class GalleryDetailInteractionController {
    var resetToken = UUID()
    var saveMessage = ""

    @ObservationIgnored private var saveTask: ImageTask?

    deinit {
        saveTask?.cancel()
    }

    func resetZoom() {
        resetToken = UUID()
    }

    func save(item: GalleryItem, slot: ImageSlot) {
        guard let imageURL = slot.knownURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.image]
        panel.nameFieldStringValue = "\(item.id)-\(slot.displayIndex).jpg"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }

        saveMessage = "保存中"
        saveTask?.cancel()
        let request = RemoteImagePipeline.shared.request(
            for: imageURL,
            priority: .veryHigh,
            configureURLRequest: GalleryRequestFactory.configureImageRequest
        )
        saveTask = RemoteImagePipeline.shared.loadData(with: request) { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let data else {
                    saveMessage = "保存失败"
                    return
                }
                do {
                    try data.write(to: target, options: .atomic)
                    saveMessage = "已保存"
                } catch {
                    saveMessage = "保存失败"
                }
            }
        }
    }
}
