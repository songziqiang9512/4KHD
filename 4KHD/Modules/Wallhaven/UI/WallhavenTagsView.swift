import AppKit

/// Lays out tag buttons in wrapping rows, like a flow layout.
@MainActor
final class WallhavenTagsView: NSView {
    var onTagClick: ((String) -> Void)?
    private var buttons: [NSButton] = []
    private var tagNames: [String] = []

    func setTags(_ tags: [String], maxWidth: CGFloat) {
        tagNames = tags
        buttons.forEach { $0.removeFromSuperview() }
        buttons = []
        for tag in tags.prefix(10) {
            let btn = NSButton(title: tag, target: self, action: #selector(tagClicked(_:)))
            btn.bezelStyle = .recessed
            btn.controlSize = .small
            btn.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            btn.sizeToFit()
            // Slightly wider for padding
            btn.frame.size.width += 12
            btn.frame.size.height = 20
            addSubview(btn)
            buttons.append(btn)
        }
        layoutButtons(maxWidth: maxWidth)
    }

    override func layout() {
        super.layout()
        layoutButtons(maxWidth: bounds.width)
    }

    private func layoutButtons(maxWidth: CGFloat) {
        guard maxWidth > 0 else { return }
        var x: CGFloat = 0
        var y: CGFloat = 0
        let spacing: CGFloat = 4
        for btn in buttons {
            if x + btn.frame.width > maxWidth && x > 0 {
                x = 0
                y += btn.frame.height + spacing
            }
            btn.frame.origin = NSPoint(x: x, y: y)
            x += btn.frame.width + spacing
        }
        let totalHeight = buttons.isEmpty ? 0 : y + (buttons.last?.frame.height ?? 0)
        frame.size.height = totalHeight
        invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: frame.height)
    }

    @objc private func tagClicked(_ sender: NSButton) {
        onTagClick?(sender.title)
    }
}
