import Foundation

struct WorkspaceWindowState: Codable {
    static let defaultsKey = "com.songziqiang.4khd.workspaceWindowState.v1"

    var isFullScreen: Bool
    var splitViewWidths: [Int]
    var isSidebarHidden: Bool
    var isDetailPanePresented: Bool
    var expandedSidebarNodeIDs: [String]

    init(
        isFullScreen: Bool,
        splitViewWidths: [Int],
        isSidebarHidden: Bool,
        isDetailPanePresented: Bool,
        expandedSidebarNodeIDs: [String]
    ) {
        self.isFullScreen = isFullScreen
        self.splitViewWidths = splitViewWidths
        self.isSidebarHidden = isSidebarHidden
        self.isDetailPanePresented = isDetailPanePresented
        self.expandedSidebarNodeIDs = expandedSidebarNodeIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isFullScreen = try container.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
        splitViewWidths = try container.decode([Int].self, forKey: .splitViewWidths)
        isSidebarHidden = try container.decode(Bool.self, forKey: .isSidebarHidden)
        isDetailPanePresented = try container.decode(Bool.self, forKey: .isDetailPanePresented)
        expandedSidebarNodeIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .expandedSidebarNodeIDs
        ) ?? ["group:线上", "group:本地"]
    }
}
