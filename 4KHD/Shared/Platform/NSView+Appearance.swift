//
//  NSView+Appearance.swift
//  4KHD
//
//  Shared NSView appearance utilities extracted from MyWallpaperX.
//  Zero business dependencies.
//

import AppKit

extension NSView {
    /// Whether the view is currently in a dark appearance mode
    /// (darkAqua or vibrantDark).
    var isDarkAppearance: Bool {
        effectiveAppearance
            .bestMatch(from: [.darkAqua, .vibrantDark])
            .map { $0 == .darkAqua || $0 == .vibrantDark } ?? false
    }
}
