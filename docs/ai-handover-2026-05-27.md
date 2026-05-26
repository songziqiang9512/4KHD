# AI Handover — 2026-05-27

> 给下一个 AI 开发助手的上下文恢复文档。先读本文，再读 `AGENTS.md`，然后开始工作。

## 项目快照

- **项目**: 4KHD — macOS 原生图片浏览 App（纯 AppKit，0 SwiftUI）
- **环境**: macOS 26+, Xcode 26+, Swift 6, SPM(Nuke)
- **构建**: `xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build`
- **文件数**: ~128 Swift 文件，MissKon 模块占 18 个
- **最新提交**: `dece945` — task cleanup, favorites observation, feed-detail callback

## 四个模块当前状态

| 模块 | 状态 | 需关注 |
|------|------|--------|
| 4KHDGallery | ✅ 完整稳定 | 参考实现，其他模块对齐标准 |
| MissKon | ✅ 核心完成 95% | 详见下文 |
| LocalLibrary | ✅ 完整稳定 | — |
| Favorites | ✅ 完整 | 独立模块，通过 FavoritesStore 桥接接入 |

## MissKon 模块 — 当前状态 95%

### 已完成的全部能力

**浏览：**
- 侧边栏 8 个分类（含收藏）+ 列表/网格双视图 + 分页加载
- 按 section 内存缓存 + 磁盘持久化（Application Support JSON）+ 1 小时过期自动刷新

**详情：**
- 渐进式加载（首页立即展示 + 后台继续解析）
- 封面→大图过渡 + 相邻图片预加载（前后各 2 张）
- 上/下张导航按钮 + 键盘方向键
- 胶片条（NSVisualEffectView + 72×96 + 动画开关）

**交互：**
- 工具栏：搜索/刷新/收藏/胶片条/列数±/分享/详情面板
- 键盘：Escape 关闭详情/清除搜索，Enter 打开详情
- 右键菜单（SF Symbols 图标）：浏览器打开/复制链接/分享
- 错误重试：footer 红色可点击 + 详情区 retry 按钮
- 搜索高亮（列表 + 网格）
- 保存图片 + 重置缩放

**收藏：**
- `MissKonFavoritesBridge` + 共享 `FavoritesStore`
- 工具栏 heart 按钮 + 菜单验证

**Inspector：**
- 标签/图片数/页数/Section/收藏状态/详情 URL

**架构对齐 Gallery：**
- feed→detail `onSelectionChanged` 回调模式
- task 完成后 nil 清理
- `NSView.performWithoutAnimation` 共享
- `WorkspaceDetailRootView` 共享

### 待做的（仅 P3）

- [ ] 单元测试（整个项目零覆盖）
- [ ] 列表/网格切换时保留滚动位置
- [ ] Gallery 页脚可参考 MissKon 添加交互式重试

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

# 统计文件数
find 4KHD -name '*.swift' | wc -l
```

### 共享层清单（2026-05-27 更新）

| 组件 | 路径 | 新增/已有 |
|------|------|-----------|
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
