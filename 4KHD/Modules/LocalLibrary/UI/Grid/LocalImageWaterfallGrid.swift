import AppKit
import SwiftUI

struct LocalImageWaterfallGrid: NSViewRepresentable {
    let items: [(originalIndex: Int, image: LocalImageItem)]
    let metadataByImageID: [LocalImageItem.ID: LocalImageMetadata]
    let selectedImageID: LocalImageItem.ID?
    let onSelect: (Int) -> Void
    let onQuickLook: (LocalImageItem) -> Void
    let onShowInfo: (LocalImageItem) -> Void

    func makeNSView(context: Context) -> LocalImageGridContainerView {
        let view = LocalImageGridContainerView()
        view.onSelect = onSelect
        view.onQuickLook = onQuickLook
        view.onShowInfo = onShowInfo
        return view
    }

    func updateNSView(_ nsView: LocalImageGridContainerView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onQuickLook = onQuickLook
        nsView.onShowInfo = onShowInfo
        nsView.update(
            items: items,
            metadataByImageID: metadataByImageID,
            selectedImageID: selectedImageID
        )
    }
}
