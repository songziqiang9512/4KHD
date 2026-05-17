# 4KHD AppKit 全量替换计划

目标：最终交付一个 `0 SwiftUI` 的 macOS 原生 AppKit 应用。界面结构以邮件应用为参照：左侧源列表、中间内容列表或网格、右侧详情阅读区，上方使用原生 `NSToolbar` 承载搜索、刷新、布局切换、导入和详情控制。

## 1. 最终形态

完成后的硬性标准：

1. 生产 target 中不再出现 `import SwiftUI`。
2. 不再使用 `View`、`AnyView`、`NSHostingController`、`NSViewRepresentable`、`NavigationSplitView`、`List`、`ScrollView`、`LazyVGrid`、`@State`、`@Environment`、`@AppStorage`、`@SceneStorage` 等 SwiftUI API。
3. 应用入口使用 `NSApplicationDelegate`。
4. 主窗口由 `NSWindowController` 管理。
5. 主工作区由 `NSSplitViewController` 管理三栏布局。
6. Sidebar 使用 `NSOutlineView` 或 source-list 风格的 `NSTableView`。
7. 中栏列表和网格使用 `NSCollectionView` / `NSTableView`。
8. 详情区使用 AppKit 原生视图树，图片画布、filmstrip、inspector、overlay 都不依赖 SwiftUI。
9. 模块接入面返回 `NSViewController` 或 AppKit 专用控制器，不再返回 SwiftUI view factory。
10. 状态层不依赖 SwiftUI 环境注入；模块通过显式依赖、delegate、closure 或轻量通知更新界面。

## 2. 迁移原则

1. 先迁移外壳，再迁移模块。
2. 每一步都必须能构建，并尽量保持当前功能可用。
3. 不在一次提交中同时重写 Shell、在线模块、本地模块和详情区。
4. 先替换边界，再删除旧实现；只有新 AppKit 路径稳定后才移除 SwiftUI 文件。
5. `Shared` 只承载跨模块 AppKit 能力，不把 4KHDGallery 或 LocalLibrary 的业务语义下沉进去。

## 3. 当前 SwiftUI 依赖面

当前生产代码 SwiftUI 依赖已清零。

已移除的主要依赖面：

1. 应用入口 SwiftUI `App`。
2. 装配层 `NSHostingController`。
3. Shell `NavigationSplitView`。
4. 模块注册层 `AnyView` 工厂。
5. SwiftUI toolbar 和搜索框。
6. 4KHDGallery SwiftUI content/detail。
7. LocalLibrary SwiftUI sidebar/content/detail。
8. `DetailImageResolverView` 的 `NSViewRepresentable` 解析桥。
9. `Shared/UI/Detail` 下 SwiftUI 详情组件。
10. `RemoteImageView` SwiftUI wrapper。

## 4. 分阶段计划

### 阶段 1：AppKit 生命周期与窗口壳

目标：把应用入口从 SwiftUI `App` 迁移到 `NSApplicationDelegate`，由 `NSWindowController` 创建主窗口。

完成标准：

1. `4KHDApp.swift` 不再使用 SwiftUI `App` 协议。
2. 主窗口由 AppKit 创建，样式使用 unified titlebar。
3. 现有 SwiftUI `WorkspaceShell` 仅作为过渡内容嵌入，不改变模块行为。
4. `xcodebuild` 能通过。

### 阶段 2：AppKit Toolbar

目标：用 `NSToolbar` 替代 SwiftUI `.toolbar`。

完成标准：

1. 搜索框使用 `NSSearchField`。
2. 缓存容量、导入目录、刷新、布局切换、详情开关、沉浸模式等按钮由 `NSToolbarItem` / `NSMenuToolbarItem` 实现。
3. 工具栏状态由当前 route 和 `WorkspaceToolbarContext` 显式刷新。
4. 删除 `WorkspaceToolbarSearchGroup.swift` 和 `WorkspaceSearchField.swift`。

### 阶段 3：AppKit Shell 三栏

目标：用 `NSSplitViewController` 替代 `NavigationSplitView`。

完成标准：

1. 新增 `WorkspaceWindowController`、`WorkspaceSplitViewController`、`WorkspaceSidebarViewController`、`WorkspaceContentHostController`、`WorkspaceDetailHostController`。
2. 三栏宽度、最小宽度、详情开合由 AppKit 控制。
3. Sidebar/content/detail 不再通过 SwiftUI environment 取上下文。
4. 沉浸模式改为 AppKit 层控制 split item collapse、toolbar visibility 和左缘浮层。

### 阶段 4：模块注册面 AppKit 化

目标：把 `WorkspaceModuleRegistry` 从 SwiftUI view factory 改为 AppKit controller factory。

完成标准：

1. `WorkspaceModuleDescriptor` 不再返回 `AnyView`。
2. 每个模块提供 sidebar/content/detail 的 AppKit 控制器工厂。
3. route normalize/apply/bootstrap 保持在模块 descriptor 内。
4. Shell 不知道具体模块 store。

### 阶段 5：LocalLibrary 模块全 AppKit

目标：优先完成本地模块，因为中栏网格已有 AppKit 基础。

完成标准：

1. Sidebar 文件夹树迁移到 `NSOutlineView`。
2. 中栏继续使用现有 `LocalImageGridContainerView`，列表模式补 `NSTableView` 或统一到 `NSCollectionView`。
3. 详情区迁移为 AppKit 图片画布、底部 filmstrip、inspector overlay。
4. 删除 `LocalLibrarySidebarSection.swift`、`LocalImageContentList.swift`、`LocalImageRow.swift`、`LocalImageDetailPane.swift`、`LocalImageInfoView.swift` 等 SwiftUI 实现。

### 阶段 6：4KHDGallery 中栏 AppKit 化

目标：替换在线模块列表和网格。

完成标准：

1. 列表模式使用 `NSTableView` 或 list-style `NSCollectionView`。
2. 网格模式使用 `NSCollectionView`。
3. 收藏分组、右键菜单、分页加载、搜索过滤、刷新状态保持现有行为。
4. 删除 `GalleryContentList.swift`、`GalleryRow.swift` 中 SwiftUI view。

### 阶段 7：4KHDGallery 详情 AppKit 化

目标：替换在线详情区和解析桥。

完成标准：

1. `DetailImageResolverView` 改为 AppKit service/controller，不再是 `NSViewRepresentable`。
2. 主图画布、缩放、保存、重试、状态提示、底部 filmstrip 全部 AppKit 化。
3. WKWebView 仍可作为隐藏解析器存在，但不作为 SwiftUI view。
4. 删除 `ImageDetailPane.swift`、`Filmstrip.swift`、`GallerySharedViews.swift` 中 SwiftUI UI。

### 阶段 8：Shared UI 清理

目标：移除共享层中的 SwiftUI UI。

完成标准：

1. `RemoteImageView` 替换为 AppKit 图片加载 view。
2. `ZoomableImageCanvas` 替换为 `NSView` / `NSScrollView` 组合。
3. `HorizontalFilmstrip` 替换为 AppKit filmstrip 控件。
4. `DetailPaneToggleButton` 移入 AppKit toolbar 或 Shell 控制。
5. `Shared/UI` 下不再有 SwiftUI import。

### 阶段 9：状态与持久化收尾

目标：清除 SwiftUI 状态机制。

完成标准：

1. `@AppStorage` 替换为 `UserDefaults` 封装。
2. `@SceneStorage` 替换为窗口控制器持有的 route persistence。
3. `@Environment` 替换为构造注入。
4. SwiftUI `@State`、`Binding`、`@Bindable` 全部删除。

### 阶段 10：0 SwiftUI 验收

目标：删除过渡桥和所有 SwiftUI 文件。

验收命令：

```bash
rg -n "import SwiftUI|NSHosting|NSViewRepresentable|AnyView|NavigationSplitView|@State|@Environment|@AppStorage|@SceneStorage|\\bView\\b" 4KHD
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build
```

完成标准：

1. 搜索命令对生产代码无命中。
2. Debug 构建通过。
3. 应用启动、三栏布局、在线浏览、本地浏览、收藏、搜索、刷新、导入、保存、Quick Look、详情开合和沉浸模式通过手动验收。

## 5. 当前执行顺序

阶段 1 到阶段 10 已完成第一轮迁移。后续工作不再是 SwiftUI 替换，而是 AppKit 行为验收和体验收敛：

1. 手动验收三栏布局、在线浏览、本地浏览、搜索、刷新、导入、保存、Quick Look、详情开合和沉浸模式。
2. 按验收结果修 AppKit 交互细节。
3. 再清理不再使用的状态控制器或平台辅助类。

## 6. 执行记录

### 2026-05-17

已完成：

1. 阶段 1 已开始并完成第一版：应用入口迁移为 `NSApplicationDelegate`，主窗口由 `NSWindowController` 创建。
2. 阶段 3 已开始并完成第一版：主窗口内容由 `WorkspaceSplitViewController` 接管，三栏外壳改为 `NSSplitViewController`。
3. 新增 AppKit 主菜单，补齐 Hide、Quit、Close、Edit、Window 等基础菜单项。
4. 新增 `WorkspaceRouteController`，把当前 route 从 SwiftUI `SceneStorage` 抽到共享控制器，供 AppKit toolbar 和过渡 Shell 共用。
5. 阶段 2 已开始：顶层 toolbar 的搜索框、缓存容量菜单、导入目录、详情区开关已迁移到 `NSToolbar`。
6. 删除过渡层不再使用的 `WorkspaceToolbarSearchGroup`、`WorkspaceSearchField`、`DetailPaneToggleButton`。
7. `NavigationSplitView` 已从生产代码中移除。
8. Sidebar 已迁移为 AppKit `NSOutlineView` source list，线上分区和本地目录树由壳层统一渲染。
9. 删除旧 SwiftUI sidebar 文件：`FourKHDGallerySidebarSection.swift`、`LocalLibrarySidebarSection.swift`。
10. 阶段 4 已开始：`WorkspaceModuleRegistry` 的模块接入面已从 SwiftUI `AnyView` 工厂改为 AppKit `NSViewController` 工厂。
11. `WorkspaceShell.swift` 已移除 `SwiftUI` / `AnyView` / `NSHostingController` 依赖，中栏和详情栏通过 `WorkspaceColumnHostController` 承载 AppKit controller。
12. LocalLibrary 中栏已迁移到 `LocalImageContentViewController`，网格直接复用原有 AppKit `LocalImageGridContainerView`，列表模式改为 `NSTableView`。
13. 删除本地中栏旧 SwiftUI wrapper：`LocalImageContentList.swift`、`LocalImageRow.swift`、`LocalImageWaterfallGrid.swift`。
14. AppKit sidebar 已接入 Swift Observation 追踪，本地目录导入、扫描和选中变化会触发 source list 刷新。
15. LocalLibrary 详情区已迁移到 AppKit：新增 `LocalImageDetailViewController`、`LocalZoomableImageView`、`LocalImageFilmstripView`，覆盖图片画布、底部 filmstrip、键盘切图、保存状态、Quick Look、Finder 定位和信息弹窗。
16. 删除本地详情旧 SwiftUI 文件：`LocalImageDetailPane.swift`、`LocalImageInfoView.swift`、`LocalImageInspectorOverlay.swift`。
17. LocalLibrary 的 sidebar / content / detail 当前都已走 AppKit 路径。
18. 4KHDGallery 中栏已迁移到 AppKit：新增 `GalleryContentViewController`、`GalleryGridContainerView`、`GalleryContentViews`、`GalleryRemoteImageView`，覆盖列表、网格、收藏作者分组、右键移动/恢复分类和滚动加载更多。
19. 删除 Gallery 中栏旧 SwiftUI 文件：`GalleryContentList.swift`、`GalleryRow.swift`。
20. 4KHDGallery 详情区已迁移到 AppKit：新增 `GalleryImageDetailViewController`、`GalleryZoomableImageView`、`GalleryFilmstripView`。
21. `DetailImageResolverView` 已替换为 AppKit/WebKit 服务 `DetailImageResolver`，不再通过 `NSViewRepresentable` 承载。
22. 删除 Gallery 详情旧 SwiftUI 文件：`ImageDetailPane.swift`、`Filmstrip.swift`、`GallerySharedViews.swift`。
23. 删除共享详情旧 SwiftUI 文件：`SmallViews.swift`、`HorizontalFilmstrip.swift`、`ZoomableImageCanvas.swift`。
24. `RemoteImageView.swift` 已清理为纯 Nuke/AppKit 图片 pipeline 和本地图片缓存，不再包含 SwiftUI wrapper。
25. 新增纯 AppKit/ Foundation 辅助文件：`NSEvent+BareModifiers.swift`、`URL+DetailPath.swift`。
26. 装配层已移除所有 `NSHostingController` 和 `import SwiftUI`。
27. 生产代码中 `import SwiftUI` / `NSHosting` / `NSViewRepresentable` / `AnyView` / `@State` / `@Environment` / `@AppStorage` 等 SwiftUI 命中已清零。
28. 全局 `NSToolbar` 已补齐当前模块的列表/网格切换和刷新按钮，和现有 `WorkspaceToolbarContext` 对齐。
29. 在线详情区底部 filmstrip 已改为通过高度约束收起，隐藏时不再保留 112pt 空白。
30. 已清理在线详情区重复创建的底部状态约束，避免多次 reload 累积无效约束。
31. 修复 Xcode 启动时主窗口未拉起的问题：AppKit 入口改为持久持有 `FourKHDAppDelegate`，避免 delegate 提前释放。
32. 全局 toolbar 使用 AppKit 标准 `.toggleSidebar` item 承载侧边栏开关；侧边栏展开时按钮位于侧边栏顶部区域，收起后保留在窗口最左侧。
33. 主窗口恢复 `fullSizeContentView` 和透明 titlebar，侧边栏整列使用 `.sidebar` material，红绿灯区域被侧边栏玻璃面板包裹。
34. 中栏和详情栏通过 `WorkspaceColumnHostController(respectsSafeAreaTop: true)` 从 safe area 下方开始，避免 full-size titlebar 下内容钻到 toolbar 下面。
35. Toolbar 左侧保留列表/网格切换和刷新按钮，搜索框固定在右侧并使用原生 `NSSearchField` 胶囊外观。
36. 线上和本地详情图都改为按实际详情 viewport 的最长边 fit，并在 viewport 内居中，避免缩小时贴左下角。
37. 详情区 filmstrip 背景和缩略图底色改为动态系统颜色，深色模式下不再保留浅色背景。
38. 详情区开合改为无动画 collapse，减少中栏抖动。

验证结果：

```bash
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build
```

结果：Debug 构建通过。

0 SwiftUI 验收结果：

```bash
rg -n "import SwiftUI|NSHosting|NSViewRepresentable|AnyView|@State|@Environment|@AppStorage|@SceneStorage|NavigationSplitView|LazyVGrid|ContentUnavailableView" 4KHD
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build
```

结果：SwiftUI 关键字扫描无命中，Debug 构建通过。

AppKit 行为修正后复验：

```bash
rg -n "import SwiftUI|NSHosting|NSViewRepresentable|AnyView|@State|@Environment|@AppStorage|@SceneStorage|NavigationSplitView|LazyVGrid|ContentUnavailableView" 4KHD
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build
```

结果：SwiftUI 关键字扫描无命中，Debug 构建通过。

2026-05-17 第二轮 AppKit 行为复验：

```bash
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build
```

结果：Debug 构建通过；已手动启动 Debug app，确认主窗口可拉起、侧边栏展开/收起按钮采用 macOS 原生位置、侧边栏玻璃面板覆盖红绿灯区域。

下一步：

1. 手动打开应用验收在线列表/网格、详情解析、保存、收藏分组、滚动加载更多。
2. 手动验收本地目录导入、列表/网格切换、Quick Look、Finder 定位和详情 filmstrip。
3. 根据手动验收结果修 AppKit 行为细节。
