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
    UI/           — 瀑布流布局、缩略图卡片、缩放图片视图、RemoteImageView、胶卷条覆盖层
      Detail/       — 详情区覆盖层组件
  Modules/      — 业务模块实现
    4KHDGallery/  — 4KHD.com 在线图库模块
    LocalLibrary/ — 本地图片模块
    Favorites/   — 收藏记录模块
    MissKon/     — misskon.com 在线图库模块
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
| 在线图库 | `MissKon` | misskon.com 标签/热门浏览、详情 HTML 解析、渐进式图片加载 |
| 本地图片 | `LocalLibrary` | 本地目录导入、扫描、metadata 读取 |
| 收藏 | `Favorites` | 收藏记录与分组，独立于业务模块 |

## 4. 共享能力清单

| 组件 | 路径 | 用途 |
|------|------|------|
| `WorkspaceTableView` | `Shared/UI/` | 统一 NSTableView 基类（menu、keyDown、live resize） |
| `WorkspaceCollectionView` | `Shared/UI/` | 统一 NSCollectionView 基类（hover、tracking area、keyDown） |
| `WorkspaceZoomableImageView` | `Shared/UI/` | 可缩放图片视图基类（pinch zoom、fit、reset） |
| `WorkspaceThumbnailWaterfallLayout` | `Shared/UI/` | 瀑布流布局 |
| `WorkspaceThumbnailGridCardView` | `Shared/UI/` | 缩略图卡片视图（图片+文字+高亮+hover） |
| `RemoteImageView` | `Shared/UI/` | 共享远程图片视图（Nuke 加载、占位符、aspectFill/Fit） |
| `DetailOverlayChromeView` | `Shared/UI/Detail/` | 详情区覆盖层圆角背景 |
| `DetailNavigationButton` | `Shared/UI/Detail/` | 详情区导航按钮（圆形毛玻璃） |
| `RemoteImagePipeline` | `Shared/Services/` | Nuke 图片加载管线 |
| `WorkspaceKeyboardHandler` | `Shared/Platform/` | 键盘事件分发 |
| `WorkspaceCoalescingQueue` | `Shared/Platform/` | 合并高频刷新 |
| `FilmstripVisibilityController` | `Shared/State/` | 胶卷条显示/隐藏动画状态 |
| `WorkspaceDetailPaneController` | `Shared/State/` | 详情窗格展开/收起 |

## 5. 变更优先级

1. 先保持底壳稳定
2. 再保证模块可独立维护
3. 再抽共享能力
4. 最后才考虑更大规模重构

## 6. 文档维护

结构方向发生实质变化时，必须同步更新 `AGENTS.md`、`README.md` 和 `docs/ai-handover-*.md`。

## 7. 最近完成的工作（2026-05-27）

### 第一轮：功能补全（P0 + P1 + P2）

**收藏接入（P0）：**
- 新建 `MissKonFavoritesBridge`（参考 GalleryFavoritesBridge）
- `MissKonFeedStore` 注入 `FavoritesStore`，`.favorites` section 从持久化收藏读取
- `MissKonGalleryStore` 新增 `isFavorite`/`toggleFavorite`
- `WorkspaceAppAssembly` 中 `FavoritesStore` 单例在 Gallery/MissKon 间共享
- 工具栏 heart 按钮支持 missKon，操作菜单新增保存/info 项
- `FourKHDGalleryStore.init()` 改为接受外部 `FavoritesStore` 参数

**MissKon Inspector（P1）：**
- 展示标签/图片数/页数/Section/收藏状态/详情 URL
- `observeState` 添加 missKon 状态追踪

**详情区重试（P1）：**
- `MissKonDetailStore.resolve(item:force:)` 添加 force 参数 + `retry()` 方法
- `MissKonZoomableImageView.showFailure(retry:)` + retryButton
- 全部解析失败时展示重试 overlay

**搜索高亮（P1）：**
- 列表/网格中搜索匹配文字黄色高亮
- 复用 `Shared/UI/highlightedAttributedString`

**缓存持久化（P2）：**
- `MissKonItem`/`MissKonSection` 支持 Codable
- `Application Support/4KHD/MissKon/feed-cache.json` 读写
- 网络刷新/加载更多成功后自动保存

**keyDown 转发（P2）：**
- 新建 `Shared/UI/Detail/WorkspaceDetailRootView` 共享基类

### 第二轮：性能优化 + Bug 修复

**Bug 修复：**
- MissKon 详情区未观察 `saveMessage`（保存状态文字不更新）
- `syncTableSelection` 的 `deselectAll` 缺少 `isApplyingSelection` 守卫

**性能优化：**
- 列表增量更新：ID 不变时跳过 `reloadData`，仅 `reloadVisibleListRows`
- 网格 `refreshVisibleItems`：元数据仅变化时更新可见卡片，避免全量重载
- 缓存时间戳 + 1 小时自动刷新，防止永久展示过期数据

**共享代码提取：**
- `NSView.performWithoutAnimation` → `Shared/Platform/NSView+AnimationSuppression.swift`

**UI 对齐：**
- MissKon 上下文菜单添加 SF Symbols 图标（safari/doc.on.doc/square.and.arrow.up）

### 第三轮：架构对齐

**feed→detail 回调模式：**
- `MissKonFeedStore.onSelectionChanged` 闭包（对齐 GalleryFeedStore）
- `MissKonGalleryStore.init` 自动布线，`select(_:)` 简化为单次委托

**Task 清理：**
- `loadTask`/`searchTask` 完成后 nil 清理

**收藏状态追踪：**
- 详情区 `observeState` 添加 `favorites.favorites` 观察

### 模块状态评估

MissKon 模块整体完成度约 95%：
- 核心浏览链路完整（侧边栏→列表/网格→分页加载→详情大图→图片切换）
- 收藏/Inspector/搜索高亮/重试/缓存持久化 全部完成
- 架构对齐 4KHDGallery（onSelectionChanged 回调、task 清理、动画抑制共享）
- 已知缺失：单元测试（P3）、列表/网格切换保留滚动位置（P3）

### 共享层清单

| 组件 | 路径 | 状态 |
|------|------|------|
| `RemoteImageView` | `Shared/UI/` | 已有 |
| `WorkspaceDetailRootView` | `Shared/UI/Detail/` | 本轮新增 |
| `NSView.performWithoutAnimation` | `Shared/Platform/` | 本轮新增 |
| `highlightedAttributedString` | `Shared/UI/` | 已有 |
| `WorkspaceThumbnailGridCardView` | `Shared/UI/` | 已有 |
| `WorkspaceZoomableImageView` | `Shared/UI/` | 已有 |
| `RemoteImagePipeline` | `Shared/Services/` | 已有 |
| `FilmstripVisibilityController` | `Shared/State/` | 已有 |
