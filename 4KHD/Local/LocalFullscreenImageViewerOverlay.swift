// Legacy overlay-based fullscreen. Superseded by macOS-native `NSWindow.toggleFullScreen`
// driven from `WorkspaceShell`, which collapses the split view to detail-only and lets
// the unified toolbar auto-hide. Kept as an empty stub to preserve Xcode project refs.

import SwiftUI

struct LocalFullscreenImageViewerOverlay: View {
    var body: some View { EmptyView() }
}
