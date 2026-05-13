import AppKit
import Combine
import SwiftUI

// MARK: - Immersive 控制器（窗内大图模式）

/// 共享给详情面板的沉浸模式控制器。改用 `ObservableObject` + `.environmentObject`，
/// 是因为 SwiftUI 工具栏对 `@Environment(.value, closure)` 偶发不可靠。
@MainActor
final class ImmersiveController: ObservableObject {
    @Published var isImmersive: Bool = false
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var peekRevealing: Bool = false

    private var nonImmersiveVisibility: NavigationSplitViewVisibility = .all
    private var peekHideWorkItem: DispatchWorkItem?

    func toggle() {
        set(!isImmersive)
    }

    func set(_ on: Bool) {
        if on {
            if !isImmersive { nonImmersiveVisibility = columnVisibility }
            peekHideWorkItem?.cancel()
            withAnimation(.easeInOut(duration: 0.22)) {
                isImmersive = true
                peekRevealing = false
            }
        } else {
            peekHideWorkItem?.cancel()
            withAnimation(.easeInOut(duration: 0.22)) {
                isImmersive = false
                peekRevealing = false
                columnVisibility = nonImmersiveVisibility
            }
        }
    }

    /// 鼠标贴到屏幕左边缘触发条 → 滑出侧栏 + 中栏。
    func revealColumns() {
        guard isImmersive else { return }
        peekHideWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.22)) {
            peekRevealing = true
        }
    }

    /// 鼠标离开侧栏 / 中栏 → 0.4s 后再收回，避免分隔条上抖动。
    func handleColumnHover(_ hovering: Bool) {
        guard isImmersive else { return }
        peekHideWorkItem?.cancel()
        if hovering {
            withAnimation(.easeInOut(duration: 0.22)) {
                peekRevealing = true
            }
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isImmersive else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                self.peekRevealing = false
            }
        }
        peekHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

/// macOS 三段式工作区外壳。普通状态使用 `NavigationSplitView`；进入沉浸模式后切换
/// 到一张 detail 占满窗口的布局，左缘鼠标触发条会把侧栏 / 中栏作为浮层滑出来。
struct WorkspaceShell: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @StateObject private var immersive = ImmersiveController()

    @SceneStorage("com.songziqiang.4khd.sidebarSelection")
    private var storedSelection: String = SidebarSelection.online(.latest).rawValue

    private var selection: SidebarSelection {
        SidebarSelection(rawValue: storedSelection) ?? .online(.latest)
    }

    private var selectionBinding: Binding<SidebarSelection?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                storedSelection = newValue.rawValue
                DispatchQueue.main.async {
                    apply(newValue)
                }
            }
        )
    }

    var body: some View {
        Group {
            if immersive.isImmersive {
                immersiveBody
            } else {
                splitBody
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .environmentObject(immersive)
        .task {
            apply(selection)
            library.refreshFromNetwork()
        }
    }

    // MARK: - 普通三段式

    private var splitBody: some View {
        NavigationSplitView(columnVisibility: $immersive.columnVisibility) {
            WorkspaceSidebar(selection: selectionBinding)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            detailColumn
                .navigationSplitViewColumnWidth(min: 560, ideal: 900)
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: - 沉浸（大图占满窗口）

    private var immersiveBody: some View {
        ZStack(alignment: .leading) {
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if immersive.peekRevealing {
                HStack(spacing: 0) {
                    WorkspaceSidebar(selection: selectionBinding)
                        .frame(width: 240)
                        .background(.bar)
                    Divider()
                    contentColumn
                        .frame(width: 320)
                        .background(.background)
                    Divider()
                }
                .shadow(color: .black.opacity(0.25), radius: 12, x: 4, y: 0)
                .transition(.move(edge: .leading))
                .onHover { hovering in immersive.handleColumnHover(hovering) }
            }

            // 6pt 的隐形左缘触发条 —— 不在 peek 状态时才显示，避免压住浮层的命中区。
            if !immersive.peekRevealing {
                Color.clear
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { immersive.revealColumns() }
                    }
            }
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selection {
        case .online:
            GalleryContentList()
        case .local:
            LocalImageContentList()
                .environmentObject(localLibrary)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch selection {
        case .online:
            ImageDetailPane()
        case .local:
            LocalImageDetailPane()
                .environmentObject(localLibrary)
        }
    }

    private func apply(_ selection: SidebarSelection) {
        switch selection {
        case .online(let section):
            if library.section != section {
                library.section = section
            }
        case .local(let folderID):
            if let folder = localLibrary.findFolder(id: folderID) {
                localLibrary.selectFolder(folder)
            }
        }
    }
}

// MARK: - Sidebar selection

enum SidebarSelection: Hashable {
    case online(GallerySection)
    case local(String)

    var rawValue: String {
        switch self {
        case .online(let section): return "online:\(section.rawValue)"
        case .local(let folderID): return "local:\(folderID)"
        }
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "online":
            guard let section = GallerySection(rawValue: parts[1]) else { return nil }
            self = .online(section)
        case "local":
            self = .local(parts[1])
        default:
            return nil
        }
    }
}

// MARK: - Sidebar

struct WorkspaceSidebar: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    @Binding var selection: SidebarSelection?

    var body: some View {
        List(selection: $selection) {
            Section("线上") {
                ForEach(GallerySection.allCases) { section in
                    Label(section.title, systemImage: systemImage(for: section))
                        .tag(SidebarSelection.online(section))
                }
            }

            Section("本地") {
                if localLibrary.roots.isEmpty {
                    Label("没有目录", systemImage: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(localLibrary.roots) { root in
                        LocalFolderSidebarRow(folder: root.tree, level: 0)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("4KHD")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importRootFolder()
                } label: {
                    Label("导入目录", systemImage: "folder.badge.plus")
                }
                .help("导入本地图片文件夹")
            }
        }
    }

    private func systemImage(for section: GallerySection) -> String {
        switch section {
        case .latest: "sparkles"
        case .popular: "flame"
        case .cosplay: "theatermasks"
        case .album: "photo.on.rectangle"
        case .favorites: "bookmark"
        }
    }

    private func importRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "导入"
        panel.message = "选择一个包含图片的文件夹"
        guard panel.runModal() == .OK, let folderURL = panel.url else { return }
        localLibrary.importRootFolder(folderURL)
    }
}

/// 侧栏中的递归本地目录项 —— 用系统 `DisclosureGroup` 表达层级。
struct LocalFolderSidebarRow: View {
    @EnvironmentObject private var localLibrary: LocalLibraryStore
    let folder: LocalFolderNode
    let level: Int

    @State private var isExpanded: Bool = true

    private var leafLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(folder.title).lineLimit(1)
                Text("\(folder.imageCount) 张")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: folder.images.isEmpty ? "folder" : "folder.fill")
                .foregroundStyle(.tint)
        }
    }

    var body: some View {
        if folder.folders.isEmpty {
            leafLabel
                .tag(SidebarSelection.local(folder.id))
                .contextMenu {
                    Button("移除目录") { localLibrary.removeFolder(folder) }
                }
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(folder.folders) { child in
                    LocalFolderSidebarRow(folder: child, level: level + 1)
                }
            } label: {
                leafLabel
                    .contextMenu {
                        Button("移除目录") { localLibrary.removeFolder(folder) }
                    }
            }
            .tag(SidebarSelection.local(folder.id))
        }
    }
}
