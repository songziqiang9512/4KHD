import AppKit

@MainActor
enum SharingPresenter {
    static func show(
        items: [Any],
        relativeTo rect: NSRect? = nil,
        of view: NSView,
        preferredEdge: NSRectEdge = .maxY
    ) {
        guard !items.isEmpty else { return }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: rect ?? view.bounds, of: view, preferredEdge: preferredEdge)
    }
}
