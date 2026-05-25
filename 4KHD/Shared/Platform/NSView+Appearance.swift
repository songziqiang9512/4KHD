//
//  NSView+Appearance.swift
//  4KHD
//
//  Shared NSView appearance utilities extracted from MyWallpaperX.
//  Zero business dependencies.
//

import AppKit
import QuartzCore

extension NSView {
    /// Whether the view is currently in a dark appearance mode
    /// (darkAqua or vibrantDark).
    var isDarkAppearance: Bool {
        effectiveAppearance
            .bestMatch(from: [.darkAqua, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }

    /// Ensures the layer's anchorPoint is at (0.5, 0.5) while keeping the
    /// frame visually unchanged. Must be called before applying
    /// transform.scale animations to avoid an offset scaling center.
    func ensureLayerAnchorCentered() {
        guard let layer, !bounds.isEmpty else { return }
        guard abs(layer.anchorPoint.x - 0.5) > 0.0001
           || abs(layer.anchorPoint.y - 0.5) > 0.0001 else { return }
        let preservedFrame = layer.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.frame = preservedFrame
        CATransaction.commit()
    }
}
