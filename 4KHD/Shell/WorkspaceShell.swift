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
    var isToolbarVisible: Bool = true

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
                isToolbarVisible = false
                // 让 NavigationSplitView 把 sidebar + content 一起收掉，detail 占满。
                columnVisibility = .detailOnly
            }
        } else {
            peekHideWorkItem?.cancel()
            withAnimation(.easeInOut(duration: 0.22)) {
                isImmersive = false
                peekRevealing = false
                isToolbarVisible = true
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

    func handleToolbarPointer(isNearTop: Bool) {
        guard isImmersive else { return }
        if isNearTop {
            withAnimation(.easeInOut(duration: 0.14)) {
                isToolbarVisible = true
            }
            return
        }

        guard isToolbarVisible else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            isToolbarVisible = false
        }
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
    @Environment(WorkspaceAppContext.self) private var appContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(OnlineCacheLimit.defaultsKey) private var onlineCacheLimitRaw = OnlineCacheLimit.gb1.rawValue
    @AppStorage("com.songziqiang.4khd.detailPanePresented.v1") private var detailPanePresentedRaw = true
    // @State 持有 @Observable 子对象 —— SwiftUI 会复用同一实例。
    @State private var immersive = ImmersiveController()
    @State private var detailPane = WorkspaceDetailPaneController()
    @State private var sidebarDisclosure = SidebarDisclosureState()
    @State private var didBootstrap = false

    @SceneStorage("com.songziqiang.4khd.sidebarSelection")
    private var storedSelection: String = ""

    private var selection: WorkspaceRoute {
        if let route = WorkspaceRoute(rawValue: storedSelection) {
            return route
        }
        return appContext.moduleRegistry.defaultRoute()
    }

    private var selectionBinding: Binding<WorkspaceRoute?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                let normalized = appContext.moduleRegistry.normalizedRoute(newValue)
                storedSelection = normalized.rawValue
                DispatchQueue.main.async {
                    apply(normalized)
                }
            }
        )
    }

    var body: some View {
        // 在 body 内 shadow 一份 @Bindable，给需要 $... 写法的地方提供 binding。
        @Bindable var immersive = immersive
        return Group {
            if immersive.isImmersive {
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView(columnVisibility: $immersive.columnVisibility) {
                    WorkspaceSidebar(selection: selectionBinding, importRootFolder: importRootFolder)
                        .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
                } content: {
                    contentColumn
                        .navigationSplitViewColumnWidth(
                            min: 280,
                            ideal: detailPane.preferredContentIdealWidth,
                            max: detailPane.preferredContentMaxWidth
                        )
                } detail: {
                    detailColumn
                        .navigationSplitViewColumnWidth(min: 560, ideal: 900)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .overlay(alignment: .leading) {
            immersivePeekChrome
        }
        .background {
            ZStack {
                ImmersiveToolbarMouseTracker(immersive: immersive)
                ImmersiveWindowToolbarVisibilityController(
                    isImmersive: immersive.isImmersive,
                    isToolbarVisible: immersive.isToolbarVisible
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                WorkspaceToolbarSearchGroup(route: selection)
            }

            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(OnlineCacheLimit.allCases) { limit in
                        Button {
                            onlineCacheLimitRaw = limit.rawValue
                            RemoteImagePipeline.shared.applyCacheLimit(limit)
                        } label: {
                            if selectedOnlineCacheLimit == limit {
                                Label(limit.title, systemImage: "checkmark")
                            } else {
                                Text(limit.title)
                            }
                        }
                    }
                } label: {
                    Label("缓存容量", systemImage: "internaldrive")
                }
                .help("设置在线图片磁盘缓存容量")
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    chooseAndImportRootFolder()
                } label: {
                    Label("导入目录", systemImage: "folder.badge.plus")
                }
                .help("导入本地图片文件夹")
            }
        }
        .environment(immersive)
        .environment(detailPane)
        .environment(sidebarDisclosure)
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            detailPane.setPresented(detailPanePresentedRaw)
            applyDetailPaneVisibility()
            // 让 WKWebView 的 cookie（CF / 站点会话）同步给 URLSession，
            // 后续子页面解析走 URLSession 直拉也带得上同一张票。
            CookieBridge.shared.start()
            let normalized = appContext.moduleRegistry.normalizedRoute(selection)
            if storedSelection != normalized.rawValue {
                storedSelection = normalized.rawValue
            }
            apply(normalized)
            appContext.moduleRegistry.bootstrapModules()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                DetailPageImageCache.shared.flush()
            }
        }
        .onChange(of: detailPane.isPresented) { _, isPresented in
            detailPanePresentedRaw = isPresented
            applyDetailPaneVisibility()
        }
        .onChange(of: immersive.isImmersive) { _, isImmersive in
            if !isImmersive {
                applyDetailPaneVisibility()
            }
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
                        WorkspaceSidebar(selection: selectionBinding, importRootFolder: importRootFolder)
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
        appContext.moduleRegistry.contentView(for: selection)
    }

    @ViewBuilder
    private var detailColumn: some View {
        appContext.moduleRegistry.detailView(for: selection)
    }

    private func apply(_ selection: WorkspaceRoute) {
        appContext.moduleRegistry.apply(selection)
    }

    private func applyDetailPaneVisibility() {
        guard !immersive.isImmersive else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            immersive.columnVisibility = detailPane.isPresented ? .all : .doubleColumn
        }
    }

    private var selectedOnlineCacheLimit: OnlineCacheLimit {
        OnlineCacheLimit(rawValue: onlineCacheLimitRaw) ?? .gb1
    }

    private func importRootFolder() {
        chooseAndImportRootFolder()
    }

    private func chooseAndImportRootFolder() {
        appContext.importRootFolder()
    }
}

private struct ImmersiveWindowToolbarVisibilityController: NSViewRepresentable {
    let isImmersive: Bool
    let isToolbarVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowProbeView(frame: .zero)
        view.onWindowChanged = { window in
            context.coordinator.apply(to: window, isImmersive: isImmersive, isToolbarVisible: isToolbarVisible)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.apply(to: nsView.window, isImmersive: isImmersive, isToolbarVisible: isToolbarVisible)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.restore()
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var originalToolbarVisibility: Bool?

        func apply(to window: NSWindow?, isImmersive: Bool, isToolbarVisible: Bool) {
            guard let window else { return }
            captureOriginalStateIfNeeded(window)
            self.window = window

            let shouldShowChrome = !isImmersive || isToolbarVisible
            if window.toolbar?.isVisible != shouldShowChrome {
                window.toolbar?.isVisible = shouldShowChrome
            }
        }

        func restore() {
            guard let window else { return }
            if let originalToolbarVisibility {
                window.toolbar?.isVisible = originalToolbarVisibility
            }
        }

        private func captureOriginalStateIfNeeded(_ window: NSWindow) {
            if originalToolbarVisibility == nil {
                originalToolbarVisibility = window.toolbar?.isVisible
            }
        }
    }

    private final class WindowProbeView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }
}

private struct ImmersiveToolbarMouseTracker: NSViewRepresentable {
    let immersive: ImmersiveController

    func makeCoordinator() -> Coordinator {
        Coordinator(immersive: immersive)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.immersive = immersive
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var immersive: ImmersiveController
        private var monitor: Any?
        private let revealDistanceFromTop: CGFloat = 72

        init(immersive: ImmersiveController) {
            self.immersive = immersive
        }

        deinit {
            uninstall()
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) {
            guard immersive.isImmersive,
                  let window = event.window ?? NSApp.keyWindow,
                  window.isKeyWindow else { return }

            let topDistance = max(window.frame.height - event.locationInWindow.y, 0)
            immersive.handleToolbarPointer(isNearTop: topDistance <= revealDistanceFromTop)
        }
    }
}

// MARK: - Sidebar

struct WorkspaceSidebar: View {
    @Environment(WorkspaceAppContext.self) private var appContext
    @Binding var selection: WorkspaceRoute?
    let importRootFolder: () -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(appContext.moduleRegistry.modules, id: \.id) { module in
                if let section = appContext.moduleRegistry.sidebarSection(
                    for: module.id,
                    selection: $selection,
                    importRootFolder: importRootFolder
                ) {
                    section
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("4KHD")
    }
}
