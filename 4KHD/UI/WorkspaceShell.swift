import AppKit
import SwiftUI

// MARK: - Immersive 控制器（窗内大图模式）

/// 共享给详情面板的沉浸模式控制器。
/// 用 Swift 5.9 的 `@Observable` —— SwiftUI 只在真正读过的字段变化时重渲染，
/// 既消除 `Combine` 的耦合，也避免了之前用 `ObservableObject` 时偶发的工具栏不可靠问题。
@MainActor
@Observable
final class ImmersiveController {
    var isImmersive: Bool = false
    var columnVisibility: NavigationSplitViewVisibility = .all
    var peekRevealing: Bool = false

    @ObservationIgnored private var nonImmersiveVisibility: NavigationSplitViewVisibility = .all
    @ObservationIgnored private var peekHideWorkItem: DispatchWorkItem?

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
                // 让 NavigationSplitView 把 sidebar + content 一起收掉，detail 占满。
                columnVisibility = .detailOnly
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

@MainActor
@Observable
final class SidebarDisclosureState {
    private var collapsedFolderIDs = Set<String>()

    func isExpanded(_ folderID: String) -> Bool {
        !collapsedFolderIDs.contains(folderID)
    }

    func setExpanded(_ isExpanded: Bool, for folderID: String) {
        if isExpanded {
            collapsedFolderIDs.remove(folderID)
        } else {
            collapsedFolderIDs.insert(folderID)
        }
    }
}

/// macOS 三段式工作区外壳。普通状态使用 `NavigationSplitView`；进入沉浸模式后切换
/// 到一张 detail 占满窗口的布局，左缘鼠标触发条会把侧栏 / 中栏作为浮层滑出来。
struct WorkspaceShell: View {
    @Environment(LibraryStore.self) private var library
    @Environment(LocalLibraryStore.self) private var localLibrary
    // @State 持有 @Observable 子对象 —— SwiftUI 会复用同一实例。
    @State private var immersive = ImmersiveController()
    @State private var sidebarDisclosure = SidebarDisclosureState()

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
        // 在 body 内 shadow 一份 @Bindable，给需要 $... 写法的地方提供 binding。
        @Bindable var immersive = immersive
        return NavigationSplitView(columnVisibility: $immersive.columnVisibility) {
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
        .frame(minWidth: 1080, minHeight: 700)
        // 不再做 Group { if immersive ... else splitBody } 的整树切换 ——
        // detail column 一直挂在同一颗 NavigationSplitView 上，沉浸只改 columnVisibility，
        // 主图区的 @State / WKWebView / 缩放偏移都不会因为进出沉浸而被重建。
        .overlay(alignment: .leading) {
            immersivePeekChrome
        }
        .environment(immersive)
        .environment(sidebarDisclosure)
        .task {
            // 让 WKWebView 的 cookie（CF / 站点会话）同步给 URLSession，
            // 后续子页面解析走 URLSession 直拉也带得上同一张票。
            CookieBridge.shared.start()
            apply(selection)
            library.refreshFromNetwork()
        }
    }

    /// 沉浸态独有的两层 overlay：左缘 6pt 触发条 + 鼠标滑近时浮出的 sidebar/content 面板。
    /// 浮层独立挂在最上面，不挤占 detail 列；离开沉浸时整层消失。
    @ViewBuilder
    private var immersivePeekChrome: some View {
        if immersive.isImmersive {
            ZStack(alignment: .leading) {
                // 占位层撑开 ZStack 的尺寸，让浮层和触发条拿到正确的 maxHeight；
                // 但必须关掉命中，否则会把整张窗口的点击都吞掉。
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

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
                    .frame(maxHeight: .infinity)
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 4, y: 0)
                    .transition(.move(edge: .leading))
                    .onHover { hovering in immersive.handleColumnHover(hovering) }
                } else {
                    // 6pt 隐形左缘触发条 —— 鼠标贴边时再把 peek 浮层吊出来。
                    Color.clear
                        .frame(width: 6, height: nil)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering { immersive.revealColumns() }
                        }
                }
            }
            .allowsHitTesting(true)
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selection {
        case .online:
            GalleryContentList()
        case .local:
            // localLibrary 已经由 App 通过 .environment(_:) 注入，子视图自动继承，
            // 不用再显式 forwarding。
            LocalImageContentList()
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch selection {
        case .online:
            ImageDetailPane()
        case .local:
            LocalImageDetailPane()
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
    @Environment(LibraryStore.self) private var library
    @Environment(LocalLibraryStore.self) private var localLibrary
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
    @Environment(LocalLibraryStore.self) private var localLibrary
    @Environment(SidebarDisclosureState.self) private var sidebarDisclosure
    let folder: LocalFolderNode
    let level: Int

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { sidebarDisclosure.isExpanded(folder.id) },
            set: { sidebarDisclosure.setExpanded($0, for: folder.id) }
        )
    }

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
            DisclosureGroup(isExpanded: isExpanded) {
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
