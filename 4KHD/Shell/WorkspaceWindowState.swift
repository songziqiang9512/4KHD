import CoreGraphics
import Foundation

struct WorkspaceWindowState: Codable {
    static let defaultExpandedSidebarNodeIDs = ["group:线上", "group:本地"]

    var isFullScreen: Bool
    var splitViewWidths: [Int]
    var presentedSplitViewWidths: [Int]?
    var isSidebarHidden: Bool
    var isDetailPanePresented: Bool
    var expandedSidebarNodeIDs: [String]

    init(
        isFullScreen: Bool,
        splitViewWidths: [Int],
        presentedSplitViewWidths: [Int]? = nil,
        isSidebarHidden: Bool,
        isDetailPanePresented: Bool,
        expandedSidebarNodeIDs: [String]
    ) {
        self.isFullScreen = isFullScreen
        self.splitViewWidths = splitViewWidths
        self.presentedSplitViewWidths = presentedSplitViewWidths
        self.isSidebarHidden = isSidebarHidden
        self.isDetailPanePresented = isDetailPanePresented
        self.expandedSidebarNodeIDs = expandedSidebarNodeIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isFullScreen = try container.decodeIfPresent(Bool.self, forKey: .isFullScreen) ?? false
        splitViewWidths = try container.decode([Int].self, forKey: .splitViewWidths)
        presentedSplitViewWidths = try container.decodeIfPresent([Int].self, forKey: .presentedSplitViewWidths)
        isSidebarHidden = try container.decode(Bool.self, forKey: .isSidebarHidden)
        isDetailPanePresented = try container.decode(Bool.self, forKey: .isDetailPanePresented)
        expandedSidebarNodeIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .expandedSidebarNodeIDs
        ) ?? Self.defaultExpandedSidebarNodeIDs
    }
}

enum WorkspaceSplitLayoutMetrics {
    static let minimumSidebarWidth: CGFloat = 180
    static let defaultSidebarWidth: CGFloat = 240
    static let defaultContentWidth: CGFloat = 430
    static let minimumContentWidth: CGFloat = 320
}

struct WorkspaceWindowStateStore {
    private enum Key {
        static let current = "com.songziqiang.4khd.workspaceWindowState.v1"
        static let legacyWidths = "com.songziqiang.4khd.workspaceSplitWidths.v1"
        static let legacySidebarHidden = "com.songziqiang.4khd.workspaceSidebarHidden.v1"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WorkspaceWindowState? {
        guard let data = defaults.data(forKey: Key.current) else { return nil }
        return try? JSONDecoder().decode(WorkspaceWindowState.self, from: data)
    }

    func save(_ state: WorkspaceWindowState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Key.current)
    }

    func legacySplitViewWidths() -> [Int]? {
        defaults.array(forKey: Key.legacyWidths) as? [Int]
    }

    func legacySidebarHidden() -> Bool {
        defaults.bool(forKey: Key.legacySidebarHidden)
    }

    func legacyDetailPanePresented() -> Bool {
        let stored = defaults.object(forKey: WorkspaceDetailPaneController.defaultsKey) as? Bool
        return stored ?? true
    }
}
