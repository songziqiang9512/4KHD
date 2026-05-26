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
| 在线图库 | `Wallhaven` | wallhaven.cc API v1 搜索浏览、分类/排序/比例/分辨率筛选、纯度门控、上传者浏览、本地收藏、详情缓存 |
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

## 7. 当前状态与开发注意事项

- `4KHDGallery`：稳定，是在线模块参考实现；支持网格列数 2-6、列表/网格切换保留位置、详情页 HTML 解析 + WKWebView 后备。
- `MissKon`：核心链路完整；支持列表/网格、分页、搜索高亮、收藏、Inspector、详情重试、磁盘列表缓存、渐进式详情加载。
- `LocalLibrary` / `Favorites`：稳定；收藏通过共享 `FavoritesStore` 持久化，业务模块间不直接依赖。
- `Wallhaven`：MVP 完整，在 `4KHD/Modules/Wallhaven/`。

### Wallhaven 模块结构

```
Modules/Wallhaven/
  Domain/WallhavenModels.swift          — Wallpaper, enums (Category/Purity/Sorting/Resolution/Ratio/Section)
  Services/
    WallhavenAPIClient.swift            — API v1: search, /w/{id}, settings, collections
    WallhavenRequestFactory.swift       — User-Agent, X-API-Key, Referer
    WallhavenFavoritesBridge.swift      — Wallpaper <-> FavoriteRecord
    WallhavenKeychain.swift             — Secure API Key storage
    WallhavenUploaderResolver.swift     — @username API search + HTML scraping fallback
  State/
    WallhavenAccountStore.swift        — API Key/purity gating (no Key → SFW only)
    WallhavenContentPreferences.swift  — layout, grid columns, filter prefs (persisted)
    WallhavenFeedStore.swift           — browse/search/pagination/favorites/uploader/detail cache
    WallhavenGalleryStore.swift        — top-level store
    WallhavenDetailInteractionController.swift — save, desktop wallpaper
  UI/
    WallhavenContentViewController.swift    — list/grid with keyboard nav
    WallhavenContentViews.swift             — list row, grid card, footer
    WallhavenGridContainerView.swift        — waterfall grid with API-proportioned cards
    WallhavenImageDetailViewController.swift — zoomable detail, uploader/source buttons
    WallhavenRemoteImageView.swift          — RemoteImageView subclass
```

### Wallhaven 关键设计

- **纯度门控**：无 API Key → 仅 SFW (purity=100)；有 Key → 可选 Sketchy/NSFW/All
- **API Key**：Keychain 安全存储 (`WallhavenKeychain`)，`isLoading` 标志避免 init 时重复写入
- **筛选**：Toolbar NSMenuToolbarItem 弹出菜单（分类/排序/比例/分辨率/纯度），选择后自动 resetAndRefresh()，偏好持久化到 UserDefaults
- **上传者浏览**：点击详情页作者按钮 → `showUploaderWorks(username:)` 保存当前状态 → API @username 搜索 → HTML 抓取兜底 → 分页 load more → 返回按钮恢复原状态+滚动位置
- **详情缓存**：`detailCache` 内存+磁盘 JSON，`resolveDetail(for:)` 优先查缓存，避免重复 `/w/{id}` 请求
- **收藏**：本地 `FavoritesStore`，`WallhavenSection.favorites` 读取 `sourceID=="wallhaven"` 记录；wallhaven.cc 在线 collections 未接入
- **网格比例**：卡片高度 = `columnWidth / wallhaven.aspectRatio`（API dimension_x/dimension_y 优先，clamp 0.15-6.0）
- **设为桌面**：详情右下角按钮，下载到临时目录后调 `LocalDesktopWallpaperSetter`
- **侧边栏**：本地 → 在线壁纸（浏览/收藏）→ [4KHD] → [MissKon]；4KHD/MissKon 默认隐藏，Settings 开关控制

### 已知局限

- Wallhaven API v1 **不支持按 uploader 过滤**；上传者浏览首选 API `@username` 搜索，失败时 HTML 抓取 `/user/{username}/uploads`
- Wallhaven 在线 collections（`/collections` API）仅 API client 预埋，无状态层/UI
- `WorkspaceThumbnailGridCardView` 新增 `workspaceThumbnailImageMode` 枚举（`.aspectFill`/`.aspectFit`），默认 `.aspectFill` 不影响其他模块

关键约束：

- 修改 Shell 集成任何模块时，先搜索 `case .模块名` 覆盖所有 switch。
- 修改任何在线模块时，以 `4KHDGallery` 的状态流和 UI 行为为参考。
- 在线模块异步结果必须按请求时的 section/query 回写，不能在 `await` 后直接读当前 section 写状态。
- 收藏桥和详情图片解析必须使用 exact/subdomain allowlist，不要用 `host.contains(...)`。
- 详情 HTML 截取不要用 `lowercased()` 产生的 `String.Index` 切原字符串；用 `NSString`/`NSRange` 或原字符串 case-insensitive range。
- 当前 Xcode 工程只有 `4KHD` App target，尚未配置 XCTest target；补单元测试前要先建测试 target。
- **生产代码 0 SwiftUI** — 不得引入 `import SwiftUI`、`NSHostingController`、`NSViewRepresentable`、`AnyView`

常用验证：

```bash
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
```
