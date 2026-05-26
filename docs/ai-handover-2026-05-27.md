# AI Handover — 2026-05-27

> 给下一个 AI 开发助手的上下文恢复文档。先读本文，再读 `AGENTS.md`，然后开始工作。

## 项目快照

- **项目**: 4KHD — macOS 原生图片浏览 App（纯 AppKit，0 SwiftUI）
- **环境**: macOS 26+, Xcode 26+, Swift 6, SPM(Nuke)
- **构建**: `xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build`
- **文件数**: ~120 Swift 文件，MissKon 模块占 16 个

## 四个模块当前状态

| 模块 | 状态 | 需关注 |
|------|------|--------|
| 4KHDGallery | ✅ 完整稳定 | 参考实现，其他模块对齐标准 |
| MissKon | ⚠️ 核心完成 85% | 本次开发重点，详见下文 |
| LocalLibrary | ✅ 完整稳定 | — |
| Favorites | ✅ 完整 | 独立模块，通过 FavoritesStore 桥接接入 |

## MissKon 模块 — 当前状态 85%

### 已完成的（17 项核心能力）

1. **侧边栏** 8 个分类：最新/热门/Cosplay/AI生成/私房摄影/秀人/花漾/收藏
2. **列表/网格** 双视图 + 分页加载（含 top30 /page/N/ 自动构造）
3. **按 section 内存缓存**：切换分类保留数据，不空白
4. **详情渐进加载**：首页先解析展示，后台继续解析剩余页
5. **封面→大图过渡**：选中图集先看封面，大图加载完平滑切换
6. **相邻图片预加载**：前后各 2 张（RemoteImagePipeline.prefetchDetailImages）
7. **保存图片**：Nuke loadData + NSSavePanel + 进度消息
8. **重置缩放**：resetToken 观察链
9. **上/下张导航**：浮层按钮（DetailNavigationButton）+ 键盘方向键
10. **键盘导航**：Escape 关闭详情/清除搜索，Enter 打开详情
11. **胶片条**：NSVisualEffectView + DetailOverlayChromeView + 72×96 + 动画开关
12. **工具栏**：搜索/刷新/胶片条开关/网格列数+/-/分享/详情面板
13. **错误重试**：footer 红色提示 + 点击重试
14. **搜索**：服务端搜索 + 分页 + 去重
15. **右键菜单**：浏览器打开/复制链接/分享
16. **代码共享**：RemoteImageView 提取到 Shared（MissKon/Gallery 各缩减到 10 行 wrapper）
17. **拖拽复制** URL

### 待做的（按优先级）

**P0 — 影响基本功能：**
- [ ] **收藏接入** — `MissKonSection.favorites` 的 siteURL 为 nil，需要：
  1. 在 `MissKonFeedStore` 中注入 `FavoritesStore`（参考 `GalleryFeedStore`）
  2. 创建 `MissKonFavoritesBridge`（参考 `GalleryFavoritesBridge`）
  3. 收藏/取消收藏操作接入工具栏的 heart 按钮
  4. 注意：收藏是独立模块，不要在 MissKon 内部重新实现收藏逻辑

**P1 — 用户体验明显缺失：**
- [ ] **MissKon Inspector** — `WorkspaceInspectorWindowController` 中 missKon case 显示空白占位。参考 Gallery Inspector 实现：展示当前图集标题/图片数/标签/详情链接
- [ ] **详情区重试** — 全部页解析失败时仅显示文字错误。应在 MissKonZoomableImageView 中添加重试按钮（参考 GalleryZoomableImageView.showFailure）
- [ ] **搜索高亮** — 列表/网格中搜索匹配文字高亮。复用 `Shared/UI/WorkspaceThumbnailGridCardView` 中的 `highlightedAttributedString`

**P2 — 细节打磨：**
- [ ] **缓存持久化** — 当前仅内存缓存，重启丢失。可将 loaded items JSON 写入 `Application Support/4KHD/MissKon/`
- [ ] **详情区 RootView** — Gallery 使用 `GalleryImageDetailRootView` 转发 keyDown。MissKon 用普通 NSView，沉浸模式下键盘事件可能丢失
- [ ] **封面 aspect ratio** — HTML 无 width/height 时回退到 0.74，实际加载后通过 `onAspectRatio` 更新

**P3 — 非紧急：**
- [ ] 单元测试（整个项目零覆盖）
- [ ] 列表/网格切换时保留滚动位置
- [ ] 详情区图片加载失败占位图 + 重试按钮

## 开发要点

### MissKon HTML 解析

网站使用 WordPress Sahifa 经典主题：
- 列表页：`<article class="item-list">` 容器，封面图 `data-src`（lazy loading），标题含 `(N photos)`
- 详情页：`<div class="entry">` 内两个 `<div class="page-link">` 夹图片，图片 `data-src`，域名 `tez.misskon.com`
- 分页：标准 WordPress `/page/N/`，top30 等特殊模板无分页 HTML 但支持 /page/N/ URL
- 详情见 `docs/misskon-page-structure.md`

### Shell 集成

新增任何模块功能时，搜索以下文件中的 `case .missKon` 确认覆盖：
- `WorkspaceToolbarHost.swift`（约 8 处 switch）
- `WorkspaceCommandValidator.swift`（约 7 处 switch）
- `WorkspaceToolbarContext.swift`（snapshot + action）
- `WorkspaceShell.swift`（布局/列数操作）
- `WorkspaceSidebarViewController.swift`（选择+图标）

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

# 查找 Gallery 参考实现（用于对齐）
rg "case \.fourKHDGallery" 4KHD/Shell 4KHD/App --glob '*.swift'

# 查找所有 switch 语句（新增 case 时使用）
rg "case \.fourKHDGallery" 4KHD --glob '*.swift' -l
```

### MissKon FeedStore 关键设计

```
MissKonFeedStore
  ├── cachedItems: [Section: [Item]]     ← 切换 section 时先读缓存
  ├── cachedNextPageURLs: [Section: URL]  ← 缓存每 section 的下一页
  ├── refreshFromNetwork()                ← 合并去重到缓存
  ├── loadMoreListIfNeeded()             ← 搜索时分流到 loadMoreSearchIfNeeded
  ├── restoreSectionCache()              ← section 切换时调用
  └── clearSearch()                       ← 恢复缓存 + 清搜索状态
```

### MissKonDetailStore 渐进加载

```
resolve(item:)
  ├── 首页：解析 → publishSlots() 立即展示
  ├── 其余页：while pendingURLs 逐个解析 → publishSlots() 增量更新
  └── 结束：isResolving = false
```

`publishSlots()` 保留当前 `selectedSlotID`（如仍在 slots 中），否则选第一个。

## 已知注意事项

1. **top30 不支持标准分页** — HTML 无分页元素，`nextPageURL` 通过检测 `articleCount >= 12` 后手动构造 `/page/N/` URL
2. **详情页双 page-link** — entry 内有两个 `<div class="page-link">`，图片在中间。`extractImageURLs` 已处理此结构
3. **MissKon 列表缓存策略** — `fetchHTML` 使用 `.reloadIgnoringLocalCacheData`（避免 WordPress 缓存页），图片加载走 Nuke 管线
4. **FilmstripVisibility** — 共享模块 `FilmstripVisibilityController`，MissKon detail view 观察 `filmstripVisibility.isPresented` 并做动画
5. **GridColumn** — MissKon 工具栏 +/- 按钮与 LocalLibrary 共用同一个 `localGridColumns` toolbar item，action 按 `currentModuleID` 派发
