# UI 改造备忘

日期：2026-05-17

## 核心目标

1. 工作区交互向 macOS Finder / Mail 靠拢。
2. 右侧详情区支持展开 / 折叠。
3. 工具栏搜索框旁边提供独立的详情区开关。
4. 详情区展开时，中栏自动避让并收缩到 2 列网格语义。
5. 详情区关闭时，中栏自动填充可用宽度。

## 当前状态

截至 2026-05-17，工作区已完成纯 AppKit 迁移：

1. `NavigationSplitView` 已移除，三栏布局由 `NSSplitViewController` 管理。
2. 详情区展开 / 折叠由 `WorkspaceDetailPaneController` 和 split item collapse 控制。
3. Toolbar 使用 AppKit `NSToolbar`，详情区开关、列表/网格切换、刷新、搜索和大图相关按钮已进入全局 toolbar。
4. 在线中栏和本地中栏都已迁移为 AppKit，分别维护自己的列表/网格实现。
5. 侧边栏使用 AppKit source list，配合 full-size titlebar 和 `.sidebar` material，保持 macOS 原生红绿灯/侧边栏开关体验。

## 关键风险

1. 详情区开合如果不是壳层状态，而是散在模块里，中栏联动一定会反复出问题。
2. 在线中栏和本地中栏虽然都已 AppKit 化，但仍是两套实现；不能先追求“同一套控件”，要先保证“同一套行为”。
3. 本地网格列数逻辑在 AppKit layout 内部，详情区联动如果继续深化，必须给 layout 一个明确的外部列策略输入。
4. full-size titlebar 下只有侧边栏应延伸进红绿灯区域，中栏和详情栏应继续从 safe area 下方开始。

## 原实施顺序

这部分已被 AppKit 迁移取代，仅保留为历史上下文：

1. 在 Shell / Shared 建立详情区布局状态。已完成第一版。
2. 在 toolbar 加入详情区开关。已完成，当前位于 AppKit `NSToolbar`。
3. `NavigationSplitView` 统一管理详情区显示 / 隐藏。已废弃，当前由 `NSSplitViewController` 管理。
4. 在线中栏根据壳层状态切换为自适应填充或 2 列受限布局。仍需后续体验验收。
5. 本地 AppKit 网格根据壳层状态切换为自适应填充或 2 列受限布局。仍需后续体验验收。
6. 验证详情区展开 / 折叠时选择、滚动、缩略图、搜索和工具栏无回归。仍需持续手动验收。

## 当前决定

1. 不强行抽统一网格组件。
2. 详情区开合保持壳层状态，不下放给模块内部自行处理。
3. 后续不再走 SwiftUI 桥接路线；所有新增 UI 默认 AppKit。
4. 侧边栏开关必须使用 AppKit 标准 `.toggleSidebar` item，避免手写按钮破坏 macOS 原生展开/收起位置。
