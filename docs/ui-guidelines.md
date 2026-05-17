# 4KHD macOS 原生 UI 规范

本文件定义 4KHD 的项目级 UI 方向。通用 macOS 技能包只能作为底层参考；本文件优先描述 4KHD 自己必须遵守的产品体验和实现边界。

适用范围：

- 主窗口
- 三栏工作区
- 侧边栏
- 工具栏
- 中栏列表 / 网格
- 右侧详情区 / 大图模式
- 后续新增模块的 macOS UI

## 1. 总目标

4KHD 要做成原生 macOS 桌面应用体验，不做 Web 风、iOS 风或自绘壳。

参考方向：

1. Mail 的三栏信息架构。
2. Finder 的 source list、工具栏和选择态。
3. Photos 的媒体浏览、详情图像区域和缩略图条。

默认判断标准：

1. 系统已经提供的侧边栏、工具栏、搜索、菜单、sheet、split view、source list、按钮、材质，不重新手绘。
2. 能用 AppKit 官方控件或系统材质实现的，不自己画背景、圆角、阴影、玻璃、标题栏。
3. UI 先满足 macOS 原生行为，再考虑 4KHD 的视觉识别。
4. 所有新增生产 UI 保持 `0 SwiftUI`。

## 2. 技术边界

当前生产代码已经迁移为 AppKit，后续不得重新引入 SwiftUI UI 层。

禁止重新引入：

1. `import SwiftUI`
2. `NSHostingController`
3. `NSHostingView`
4. `NSViewRepresentable`
5. `NSViewControllerRepresentable`
6. `AnyView`
7. SwiftUI 状态机制，如 `@State`、`@Binding`、`@Environment`、`@AppStorage`

允许和优先使用：

1. `NSWindow`
2. `NSToolbar`
3. `NSToolbarItem`
4. `NSSearchToolbarItem`
5. `NSTrackingSeparatorToolbarItem`
6. `NSMenuToolbarItem`
7. `NSSplitViewController`
8. `NSSplitViewItem`
9. `NSOutlineView`
10. `NSTableView`
11. `NSCollectionView`
12. `NSVisualEffectView`
13. `NSButton`
14. `NSSegmentedControl`
15. `NSMenu` / `NSMenuItem`

## 3. 官方 API 优先级

实现 UI 前必须先判断是否有官方控件或系统行为可用。

优先级：

1. AppKit 官方控件和 window / toolbar / split view API。
2. 系统材质和 semantic color。
3. 项目内已有 AppKit 封装。
4. 轻量自定义内容视图。
5. 最后才是完全自绘。

可以自绘的范围：

1. 图片内容本身。
2. 业务卡片内部的内容排版。
3. 图片缩略图裁切和选择边框。
4. 4KHD 业务状态图标。

不应自绘的范围：

1. 窗口标题栏。
2. 工具栏背景。
3. 侧边栏背景。
4. source list 行选择态。
5. 搜索框外观。
6. 系统按钮 chrome。
7. sheet / alert / menu。
8. split view 分割线基础行为。

## 4. 主窗口

主窗口应保持标准 macOS document/browser window 感觉。

要求：

1. 使用标准 `NSWindow` 标题栏和红黄绿窗口控制。
2. 使用 `.fullSizeContentView` 时，侧边栏材质必须自然延伸到标题栏区域，包裹红黄绿按钮所在高度。
3. 工具栏使用 `NSToolbar`，不要在内容区顶部伪造一条工具栏。
4. 工具栏背景、渐变、阴影和分隔效果交给系统。
5. 不要给根窗口和 split 根视图刷不透明自定义背景。
6. 窗口最小尺寸必须保护三栏基本可用性，不能让某一栏被拖到不可恢复。

## 5. 三栏结构

4KHD 的默认信息架构是三栏：

1. 左栏：source list 侧边栏。
2. 中栏：当前模块内容列表或网格。
3. 右栏：图片详情 / 大图浏览。

布局优先级：

1. 侧边栏优先级最高。
2. 中栏优先级高于详情栏。
3. 详情栏可以关闭或隐藏，但关闭后必须能通过原生工具栏按钮恢复。
4. 中栏不能因为拖动详情分割线而永久消失。
5. 侧边栏收起后必须保留可恢复入口。

实现要求：

1. 优先使用 `NSSplitViewController` 和 `NSSplitViewItem`。
2. 侧边栏使用 `NSSplitViewItem(sidebarWithViewController:)`。
3. 分割线行为优先依赖系统 split view API，不用大量手写位置猜测。
4. 如果系统 API 不足，先查 Apple 文档和原生应用行为，再做最小补充。

## 6. 侧边栏

侧边栏目标是 Mail / Finder 风格的 source list。

要求：

1. 使用 `NSOutlineView`。
2. `outlineView.style = .sourceList`。
3. 背景使用 `NSVisualEffectView` 的 `.sidebar` 材质。
4. 行必须轻量、可扫。
5. 每行最多一个 leading icon。
6. 每行一行主标题，最多一行短辅助信息。
7. 不使用卡片式侧边栏行。
8. 不在侧边栏行里塞多列元数据、多个工具图标或复杂状态。
9. 行选择态交给 source list 系统行为。

侧边栏按钮：

1. 侧边栏展开时，开关按钮应处于侧边栏顶部区域，并贴近侧边栏右侧。
2. 侧边栏关闭时，开关按钮应保留在红黄绿旁边附近，作为恢复入口。
3. 尽量使用 `NSToolbarItem.Identifier.toggleSidebar`、`NSTrackingSeparatorToolbarItem` 和系统 split view 行为。
4. 不用很小的自定义点击区域冒充系统按钮。

## 7. 工具栏

工具栏必须是系统工具栏。

要求：

1. 使用 `NSToolbar`。
2. 搜索使用 `NSSearchToolbarItem`，不把 `NSSearchField` 塞进普通 view item。
3. 侧边栏分割追踪使用 `NSTrackingSeparatorToolbarItem`。
4. 菜单型工具项使用 `NSMenuToolbarItem`。
5. 列表 / 网格切换使用 `NSSegmentedControl` 或等价系统 toolbar item。
6. 工具栏按钮优先使用 SF Symbols。
7. 工具栏图标 tint 必须有语义，不为了装饰乱上色。
8. 不手写工具栏背景、渐变、阴影、玻璃和分隔线。

工具栏功能归属：

1. 侧边栏开关属于窗口 / shell。
2. 详情栏开关属于窗口 / shell。
3. 搜索属于当前模块，但入口在系统工具栏最右侧。
4. 列表 / 网格切换和刷新属于中栏内容控制，应靠工具栏左侧内容控制组。
5. 导入、缓存等次级功能可以放工具栏或菜单，但不能挤占主流程。

## 8. 中栏内容

中栏承载模块内容，不模拟移动端卡片瀑布流。

列表模式：

1. 使用 `NSTableView`。
2. 选择态、键盘上下移动、右键菜单要符合 macOS 习惯。
3. 单行内容保持可扫，标题和关键元数据优先。

网格模式：

1. 使用 `NSCollectionView`。
2. 图片缩略图和业务卡片可以自定义，但滚动、选择、键盘移动应保持 macOS 习惯。
3. 网格卡片不要做过重的外层浮卡视觉。

## 9. 详情区

详情区主要服务图片查看。

要求：

1. 图片区域背景固定为黑色或系统认可的媒体背景，不跟随图片内容生成黑边或伪背景。
2. 大图按可用详情区域最长边适应，默认居中。
3. 下方缩略图条打开时，大图可用区域的下边界是缩略图条上方，不是窗口底边。
4. 上一张 / 下一张按钮应跟随大图可用区域的视觉中心。
5. 切换图片后，缩放应回到基准适配状态。
6. “还原”应回到基准适配状态，不是原始像素尺寸。
7. 小于 1 的缩放只允许短暂到约 0.8，并回弹到 1。
8. 从 1 到 0.8 的缩放围绕画面中心；放大时可以围绕鼠标位置。

详情区浮动控制：

1. 工具按钮浮在图片上方。
2. 不额外加黑色长条背景。
3. 浮动 chrome 使用 `NSVisualEffectView` 系统材质。
4. 按钮使用原生 `NSButton`，不要纯自绘圆形点击区。

缩略图条：

1. 背景使用系统玻璃 / HUD 材质。
2. 深色模式下不得保留浅色固定背景。
3. 缩略图序号和轻量浮层使用系统材质，不手写 `windowBackgroundColor.withAlphaComponent`。

## 10. 菜单、快捷键和命令

重要操作不能只存在于一个手势或一个浮动按钮里。

要求：

1. 常用窗口操作要有菜单或工具栏入口。
2. 图片导航、Quick Look、Finder 显示、保存等桌面操作应考虑快捷键或菜单路径。
3. 右键菜单使用 `NSMenu` / `NSMenuItem`。
4. 菜单项图标使用 SF Symbols 时保持模板图标。

## 11. 文件和边界

大型 UI 文件必须拆分。

要求：

1. `App` 只负责应用入口和场景装配。
2. `Shell` 只负责窗口、路由、三栏布局和全局工具栏。
3. `Shared/UI` 只放跨模块且不带业务语义的 UI 基础件。
4. `Modules/*/UI` 只放模块自己的界面。
5. 单文件超过约 300 行时，新增逻辑前优先考虑拆分。
6. 不把工具栏、侧边栏、详情区、大图交互继续塞进同一个文件。

## 12. 检查清单

每轮 UI 改动结束前至少检查：

```sh
rg -n "import SwiftUI|NSHostingController|NSHostingView|NSViewRepresentable|NSViewControllerRepresentable|AnyView|@State|@Binding|@Environment|@AppStorage|@SceneStorage" 4KHD --glob '*.swift'
```

```sh
rg -n "windowBackgroundColor\\.withAlphaComponent|toolStack\\.layer|counterLabel\\.layer|statusLabel\\.layer|indexLabel\\.layer|draw\\(|drawRect|CAGradientLayer|NSBezierPath" 4KHD/App 4KHD/Shell 4KHD/Modules 4KHD/Shared
```

```sh
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
```

还必须至少启动一次 Debug app，确认：

1. 主窗口能拉起。
2. 工具栏可见。
3. 侧边栏可见或有恢复入口。
4. 中栏可操作。
5. 详情栏可见或有恢复入口。
6. 深色模式下系统材质没有明显浅色残留。

## 13. 参考技能来源

以下技能包内容可作为 macOS 原生实现参考，但不能覆盖本项目 `0 SwiftUI` 和 AppKit 实现边界：

1. `build-macos-apps:swiftui-patterns`
2. `build-macos-apps:liquid-glass`
3. `build-macos-apps:window-management`
4. `build-macos-apps:view-refactor`
5. `build-macos-apps:appkit-interop`
6. `build-macos-apps:build-run-debug`

当技能包与本文件冲突时，以本文件为准。
