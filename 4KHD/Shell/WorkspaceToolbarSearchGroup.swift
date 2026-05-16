import SwiftUI

struct WorkspaceToolbarSearchGroup: View {
    @Environment(WorkspaceAppContext.self) private var appContext
    let route: WorkspaceRoute

    var body: some View {
        HStack(spacing: 8) {
            WorkspaceSearchField(
                text: searchBinding,
                prompt: prompt,
                onSubmit: { appContext.toolbarContext.submitSearch(for: route.moduleID) }
            )
            .frame(width: 240)

            DetailPaneToggleButton()
                .labelStyle(.iconOnly)
        }
    }

    private var prompt: String {
        switch route.moduleID {
        case .fourKHDGallery:
            return "搜索 4KHD"
        case .localLibrary:
            return "搜索本地图片"
        }
    }

    private var searchBinding: Binding<String> {
        Binding(
            get: { searchText },
            set: { appContext.toolbarContext.setSearchText($0, for: route.moduleID) }
        )
    }

    private var searchText: String {
        switch appContext.toolbarContext.snapshot(for: route.moduleID) {
        case .gallery(let snapshot):
            return snapshot.searchText
        case .local(let snapshot):
            return snapshot.searchText
        }
    }
}
