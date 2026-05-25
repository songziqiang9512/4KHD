# 4KHD 顶层开发规范

本文件是 4KHD 项目的顶层开发规范，由 AI 开发助手维护。

适用范围：整个仓库、所有模块、所有结构调整/重构/功能开发/Bug 修复。

## 1. 总体原则

4KHD 的长期方向是建设一个可持续发展的 macOS 原生桌面工作区应用底壳。

1. 底壳独立。2. 模块独立。3. 公共能力独立。
4. 删除任意模块，不应影响其他模块运行。
5. 新增模块，不应要求重写底壳。
6. **所有能用 macOS 系统能力做成的功能，绝不自定义自己画。50 行能搞定的功能绝不写 200 行。**

## 2. 架构

```text
4KHD/
  App/          — 应用入口、场景组装、偏好设置窗口、Inspector 窗口
  Shell/        — 工作区底壳、模块路由、三栏布局、侧边栏、工具栏
    Toolbar/      — NSToolbar 实现（WorkspaceToolbarHost）
    Immersive/    — 窗内大图模式控制器
    WorkspaceLayout/ — 侧边栏展开状态
  Shared/       — 跨模块可复用能力
    Platform/     — 系统桥接（键盘、QuickLook、壁纸设置、Inspector、CoalescingQueue、NSView/AppKit 扩展）
    Services/     — 图片缓存、远程图片加载、Cookie 桥接
    State/        — 详情区状态、胶卷条可见性
    UI/           — 瀑布流布局、缩略图卡片、缩放图片视图、胶卷条覆盖层
      Detail/       — 详情区覆盖层组件
  Modules/      — 业务模块实现
    4KHDGallery/  — 在线图库模块
     LocalLibrary/ — 本地图片模块
     Favorites/   — 收藏记录模块
```

### 模块内部结构

每个业务模块应遵循：`Domain / State / Services / UI` 分层。

- `Domain` — 数据模型
- `State` — Store、交互控制器、偏好设置
- `Services` — 网络请求、解析、缓存
- `UI` — NSViewController、NSView、布局

### 约束

1. `App` 只放应用入口与场景组装
2. `Shell` 只放工作区底壳、模块路由、共享布局容器
3. `Shared` 只放至少两个模块使用的通用能力，不带强业务语义
4. `Modules` 只放业务模块实现，模块间不直接依赖
5. **生产代码 `0 SwiftUI`** — 不得引入 `import SwiftUI`、`NSHostingController`、`NSViewRepresentable`、`AnyView`

## 3. 当前模块

| 模块 | 名称 | 说明 |
|------|------|------|
| 在线图库 | `4KHDGallery` | 4KHD 网站栏目浏览、详情页解析、图片提取 |
| 本地图片 | `LocalLibrary` | 本地目录导入、扫描、metadata 读取 |
| 收藏 | `Favorites` | 收藏记录与分组，独立于业务模块 |

## 4. 变更优先级

1. 先保持底壳稳定
2. 再保证模块可独立维护
3. 再抽共享能力
4. 最后才考虑更大规模重构

## 5. 文档维护

结构方向发生实质变化时，必须同步更新 `AGENTS.md` 和 `README.md`。

## 6. 最近完成的工作（2026-05-26）

以下是在本次开发会话中完成的所有改进，供下次继续开发时参考上下文：

### UI 稳定性（30 项）

- 工具栏增量更新替代完全重建，消除图标闪烁
- 胶卷条 `syncSelection` 不再强制居中覆盖用户滚动
- 沉浸模式工具栏添加 0.6s 延迟隐藏，消除闪烁
- 移除滚动回调中的 hover 状态清除（由 `mouseExited` 处理）
- 胶卷条显示/隐藏添加 0.2s ease-in-out 动画
- 缩放弹回使用 `allowsImplicitAnimation` 确保动画生效
- 捏合缩放使用事件位置替代视口中心，跟手
- 卡片缩放动画先移除旧动画避免反弹
- Live-resize 滚动条切换改为 no-op（`autohidesScrollers` 已处理）
- 启动时在 `viewDidLoad` 恢复分割宽度，消除默认→恢复布局闪烁
- GalleryContentVC 行不变时跳过 `gridView.update()`，使用轻量 `refreshMetadata()`
- 瀑布流列重映射改为标准最短列优先算法
- 侧边栏仅节点结构变化时才 `reloadData()`
- 详情视图添加 `WorkspaceCoalescingQueue` 合并快速刷新
- 图片切换保留当前图片直到新图加载完成
- 滚动夹紧仅从上方限制（负 Y），不再从下方对抗用户滚动
- 消除 `layout()` 中的双布局循环（`lastFitSize` guard）
- `applySnapshot` 改为同步，消除 `DispatchQueue.main.async` 数据源窗口
- 表行动画同时有插入和删除时 fallback 到 `reloadData()`
- Live-resize 后用 `clearVisibleHoverState()` 替代 `syncVisibleHoverState`
- 缩略图加载保留旧图片直到新图片就绪，消除复用闪烁
- 网格→列表切换保存/恢复滚动位置
- 移除热路径中的强制 `layoutSubtreeIfNeeded` 和 `needsLayout`
- 移除无效的 `animator().isCollapsed` 调用
- `viewDidAppear` 中移除冗余的 `Task` 包装

### UI 美观度（4 项）

- 添加 `viewDidChangeEffectiveAppearance` 到缺失的视图
- 卡片渐变适配 light/dark 模式，hover 边框使用 `controlAccentColor`
- 统一 Gallery/Local 胶卷条间距（8pt）、圆角（7）、字体（10pt）
- 添加 `NSVisualEffectView(.titlebar)` 提供标准半透明标题栏

### 内存/鲁棒性（4 项）

- 修复 `DetailImageResolver` retain cycle（`[weak self]`）
- `GalleryDetailInteractionController` 添加 `deinit` 取消 `saveTask`，Nuke 回调使用 `Task { @MainActor }`
- 添加 `failedThumbnailSignatures` 缓存避免反复解码失败文件
- 修复 `self?.` 在非可选上下文的编译错误

### 错误处理/键盘/无障碍（7 项）

- `GalleryFeedStore` 和 `GalleryDetailStore` 添加 `errorMessage` 属性
- `WorkspaceKeyboardHandler` 添加 Escape/Tab/Enter 支持
- 10 个 SF Symbol 图标添加 `accessibilityDescription`
- 偏好设置窗口高度优化
- 侧边栏组标题 leading inset 4→12pt
- `WorkspaceColumnHostController` 添加 vibrancy 层

### MyWallpaperX 移植（6 项）

- Inspector 添加格式列、可选中值、样式化缺失文件警告
- 新建 `NSView+Appearance.swift`（`isDarkAppearance`、`ensureLayerAnchorCentered`）
- 新建 `ModalPresentation.swift`（统一 alert 样式）
- 瀑布流布局添加 `hoverScaleFactor` 动态间距
- 网格选择刷新改为 diff-based（仅更新状态变化项）

### 工具栏精简（3 项）

- 移除列表/网格切换按钮（已在偏好设置中）
- 收藏图标 `bookmark` → `heart`/`heart.fill`（已收藏红色实心）
- 排序图标 `arrow.up.arrow.down` → `line.3.horizontal.decrease`
- 移除缓存容量按钮（已在偏好设置中）

### 胶卷条改进（2 项）

- 仅在选中项超出可见区域时才滚动（不再频繁居中）
- 同数量时用 `reloadItems` 替代 `reloadData` 避免销毁交互中的 cell
