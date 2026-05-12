import SwiftUI

struct LocalLibraryWorkspaceView: View {
    @EnvironmentObject private var localLibrary: LocalLibraryStore

    var body: some View {
        HStack(spacing: 0) {
            LocalFolderPane()
                .frame(width: 330)
                .background(.ultraThinMaterial)

            Divider()

            LocalImageDetailPane()
                .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            LocalFullscreenImageViewerOverlay()
        }
    }
}
