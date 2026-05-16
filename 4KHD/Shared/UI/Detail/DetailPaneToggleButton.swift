import SwiftUI

struct DetailPaneToggleButton: View {
    @Environment(WorkspaceDetailPaneController.self) private var detailPane

    var body: some View {
        Button {
            detailPane.toggle()
        } label: {
            Label(
                detailPane.isPresented ? "隐藏详情区" : "显示详情区",
                systemImage: "sidebar.right"
            )
        }
        .help(detailPane.isPresented ? "隐藏右侧详情区" : "显示右侧详情区")
    }
}
