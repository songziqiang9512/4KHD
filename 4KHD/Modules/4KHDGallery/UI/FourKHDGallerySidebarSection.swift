import SwiftUI

struct FourKHDGallerySidebarSection: View {
    @Binding var selection: WorkspaceRoute?

    var body: some View {
        Section("线上") {
            ForEach(GallerySection.allCases) { section in
                Label(section.title, systemImage: section.sidebarSystemImage)
                    .tag(WorkspaceRoute(moduleID: .fourKHDGallery, itemID: section.rawValue))
            }
        }
    }
}
