import AppKit
import QuickLook
import QuickLookUI

@MainActor
final class LocalQuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = LocalQuickLookController()

    private var previewURL: URL?

    private override init() {
        super.init()
    }

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func open(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        previewURL = url
        let ownerWindow = NSApp.keyWindow ?? NSApp.mainWindow
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.becomesKeyOnlyIfNeeded = true
        panel.reloadData()
        panel.orderFront(nil)
        ownerWindow?.makeKey()
        DispatchQueue.main.async {
            ownerWindow?.makeKey()
        }
    }

    func syncVisible(url: URL?) {
        guard isVisible,
              let url,
              FileManager.default.fileExists(atPath: url.path),
              previewURL != url else { return }
        previewURL = url
        QLPreviewPanel.shared()?.reloadData()
    }

    func close() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard let event, event.hasBareKeyModifiers else { return false }
        switch event.keyCode {
        case 53:
            close()
            return true
        default:
            return false
        }
    }
}
