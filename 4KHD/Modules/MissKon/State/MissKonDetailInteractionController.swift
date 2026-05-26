import AppKit

@MainActor
final class MissKonDetailInteractionController {
    private var saveTask: Task<Void, Never>?

    deinit {
        saveTask?.cancel()
    }

    func save(imageURL: URL) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = imageURL.lastPathComponent
        panel.begin { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            self?.saveTask = Task { @MainActor [weak self] in
                var request = URLRequest(url: imageURL)
                MissKonRequestFactory.configureImageRequest(&request)
                do {
                    let (data, _) = try await URLSession.shared.data(for: request)
                    try data.write(to: destination)
                } catch {
                    if !Task.isCancelled {
                        let alert = NSAlert()
                        alert.messageText = "保存失败"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                }
                self?.saveTask = nil
            }
        }
    }
}
