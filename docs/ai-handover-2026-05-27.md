# AI Handover — 2026-05-27

> 给下一个 AI 开发助手的上下文恢复文档。先读本文，再读 `AGENTS.md`，然后开始工作。

## 项目快照

- **项目**: 4KHD — macOS 原生图片浏览 App（纯 AppKit，0 SwiftUI）
- **环境**: macOS 26+, Xcode 26+, Swift 6, SPM(Nuke)
- **构建**: `xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build`
- **文件数**: ~130 Swift 文件，MissKon 模块占 18 个
- **最新提交**: `2e9065b` — 10 个提交在本次会话中

## 四个模块当前状态

| 模块 | 状态 | 说明 |
|------|------|------|
| 4KHDGallery | ✅ 完整稳定 | 参考实现，本轮新增 gridColumnCount 支持 |
| MissKon | ✅ 完成度 98% | 核心链路完整，数据安全审计通过 |
| LocalLibrary | ✅ 完整稳定 | — |
| Favorites | ✅ 完整 | 独立模块，共享 FavoritesStore，域名验证防泄漏 |

## MissKon 模块 — 当前状态 98%

### 已完成的全部能力

**浏览：** 侧边栏 8 分类 + 列表/网格双视图 + 分页加载 + section 缓存 + 磁盘持久化
**详情：** 渐进加载 + 封面过渡 + 相邻预加载 + 导航按钮 + 键盘 + 胶片条 + 保存/缩放
**交互：** 工具栏全功能 + 搜索高亮 + 错误重试(footer+详情区) + 右键菜单(SF Symbols)
**收藏：** MissKonFavoritesBridge + 共享 FavoritesStore + 域名验证防泄漏
**Inspector：** 标签/图片数/页数/Section/收藏状态/URL
**数据安全：** NSString API 防 String.Index crash + resolvePageURLs 子页修正 + force-unwrap 消除

### 关键设计决策

1. **feed→detail 回调模式：** `onSelectionChanged` 闭包，对齐 GalleryFeedStore。多个路径自动通知详情更新。
2. **缓存策略：** `Application Support/4KHD/MissKon/feed-cache.json`，含时间戳 1h 过期自动刷新。
3. **收藏隔离：** 两桥均需 `detailURL.host` 域名验证，防止跨模块记录泄漏。
4. **详情切换：** `resolve()` 中同步创建初始占位 slot（coverURL），避免空状态闪烁。
5. **详情面板：** 同模块内 route 变化不重建 detailController，跟踪 `lastDetailModuleID`。

### Shell 集成点

搜索 `case .missKon` 确认覆盖的文件：
- `WorkspaceToolbarHost.swift` — 工具栏按钮（列数/favorite/刷新）
- `WorkspaceCommandValidator.swift` — 菜单验证
- `WorkspaceToolbarContext.swift` — snapshot + action
- `WorkspaceShell.swift` — 布局/列数操作 + detail 复用
- `WorkspaceSidebarViewController.swift` — 选中态 routeMatches
- `WorkspaceSidebarNode.swift` — 节点定义

### 常用命令

```bash
# 构建
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build

# 清理
rm -rf ~/Library/Developer/Xcode/DerivedData/4KHD-*

# 验证 0 SwiftUI
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'

# 查找 MissKon 集成点
rg "case \.missKon" 4KHD/Shell 4KHD/App --glob '*.swift'

# 查找 Gallery 参考实现
rg "case \.fourKHDGallery" 4KHD/Shell 4KHD/App --glob '*.swift'

# 统计文件数
find 4KHD -name '*.swift' | wc -l
```

### 已知注意事项

1. **HTML 解析风险：** MissKonDetailResolver.extractImageURLs 已改用 NSString API 防 crash，但 entry div 匹配仍依赖特定 class name。
2. **子页 URL：** resolvePageURLs 已修正为从 baseURL 剥离页面号，但依赖 `firstMatch(currentRegex)` 正确识别当前页。
3. **收藏域名验证：** 两桥均验证 `detailURL.host`，新增模块需同步添加。
4. **详情面板复用：** `lastDetailModuleID` 跟踪在 WorkspaceShell 中，跨模块切换时正确重建。
5. **缓存过期：** `cacheMaxAge = 3600`（1 小时），仅对网络刷新章节生效，收藏 section 始终实时读取 FavoritesStore。

### 共享层清单

| 组件 | 路径 | 状态 |
|------|------|------|
| `RemoteImageView` | `Shared/UI/` | 已有 |
| `WorkspaceDetailRootView` | `Shared/UI/Detail/` | 本轮新增 |
| `NSView.performWithoutAnimation` | `Shared/Platform/` | 本轮新增 |
| `highlightedAttributedString` | `Shared/UI/` | 已有 |
| `WorkspaceThumbnailGridCardView` | `Shared/UI/` | 已有 |
| `WorkspaceZoomableImageView` | `Shared/UI/` | 已有 |
| `WorkspaceTableView` / `WorkspaceCollectionView` | `Shared/UI/` | 已有 |
| `RemoteImagePipeline` | `Shared/Services/` | 已有 |
| `DetailPageImageCache` | `Shared/Services/` | 已有 |
| `FilmstripVisibilityController` | `Shared/State/` | 已有 |
| `WorkspaceDetailPaneController` | `Shared/State/` | 已有 |
| `WorkspaceKeyboardHandler` | `Shared/Platform/` | 已有 |
| `WorkspaceCoalescingQueue` | `Shared/Platform/` | 已有 |

### MissKon 文件结构

```
Modules/MissKon/
  Domain/
    MissKonModels.swift           — MissKonSection, MissKonItem, MissKonImageSlot
  State/
    MissKonFeedStore.swift        — 列表数据 + 缓存 + 搜索 + 收藏桥接
    MissKonDetailStore.swift      — 详情页解析 + slot 管理 + retry
    MissKonGalleryStore.swift     — 门面：组合 feed/detail/favorites
    MissKonContentPreferences.swift — 布局 + 列数偏好
    MissKonDetailInteractionController.swift — 保存/缩放交互 (@Observable)
  Services/
    MissKonListResolver.swift     — 列表页 HTML 解析 + 搜索
    MissKonDetailResolver.swift   — 详情页 HTML 解析 (NSString API)
    MissKonRequestFactory.swift   — URLRequest 配置 (Cookie/UA/Referer)
    MissKonFavoritesBridge.swift  — MissKonItem ↔ FavoriteRecord 转换
  UI/
    MissKonContentViewController.swift — 列表/网格内容视图
    MissKonContentViews.swift     — 列表行/网格项/页脚视图
    MissKonGridContainerView.swift — 网格容器 (NSCollectionView)
    MissKonImageDetailViewController.swift — 详情区视图控制器
    MissKonZoomableImageView.swift — 可缩放图片视图
    MissKonFilmstripView.swift    — 胶卷条视图
    MissKonRemoteImageView.swift  — 远程图片视图 (Nuke wrapper)
```
