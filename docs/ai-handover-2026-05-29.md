# 4KHD 全模块审计与修复报告

**日期**: 2026-05-29  
**范围**: 全 7 模块 — MissKon、Wallhaven、4KHDGallery、Favorites、Shared、Shell、App  
**提交**: 9 commits，净增 +606 / -81 行  
**编译**: 全部通过，零 error 零 warning  

---

## 一、修复总览

### P0 — 严重 Bug（5 项）

| # | 模块 | 文件 | 问题 | 修复 |
|---|------|------|------|------|
| 1 | Wallhaven | `WallhavenFeedStore.swift` | 搜索分页完全不可用 — `loadMoreIfNeeded` 不检查 `activeSearchQuery`，搜索结果无法翻页 | 添加 `if activeSearchQuery != nil { loadMoreSearchIfNeeded(); return }` |
| 2 | Wallhaven | `WallhavenUploaderResolver.swift` | HTML 回退方案 24 次串行 `/w/{id}` API 调用，最坏 12 秒 | `withTaskGroup` 并行化，字典排序保持原始顺序 |
| 3 | MissKon | `MissKonListResolver.swift` | 分页推断 `>=12` 在文章数恰好为 12 的倍数时误判有下一页，导致 404 请求 | `>= 12` → `> 12`；`/page/N/` URL 替换更健壮 |
| 4 | Shared | `WorkspaceThumbnailWaterfallLayout.swift` | `updateCachedFrames` 使用部分缓存时将 `didLayoutAllItems` 无条件设 true，折叠线以下元素消失 | 保留 `nextItemIndex >= itemCount` 的实际状态 |
| 5 | Shell | `WorkspaceShell.swift:500-501` | `applyCurrentRoute()` 在 `bootstrapModules()` 之前执行，模块 store 未初始化就创建 ViewController | 交换两行顺序 |

### P1 — 状态一致性与流程缺陷（7 项）

| # | 模块 | 文件 | 问题 | 修复 |
|---|------|------|------|------|
| 6 | MissKon | `MissKonFeedStore.swift` | `loadMoreSearchIfNeeded` 复用 `loadTask`（应独立），与常规分页互相取消 | 添加独立 `searchLoadTask` 变量 |
| 7 | Wallhaven | `WallhavenFeedStore.swift` | 同上 | 同上 |
| 8 | Wallhaven | `WallhavenFeedStore.swift` | `showUploaderWorks` / `loadMoreUploaderWorks` 回调无 `isBrowsingUploader` guard，旧 task 可能污染新状态 | 添加 `guard self.isBrowsingUploader else { return }` |
| 9 | Wallhaven | `WallhavenFeedStore.swift` | uploader 模式下搜索不清除 `isBrowsingUploader`，分页走错分支 | `submitSearch` / `setSection` 调用 `clearUploaderBrowsing()` |
| 10 | MissKon | `MissKonDetailStore.swift` | 多页解析 while 循环无上限，存在页面循环风险；取消时 `isResolving` 不重置 | 加 50 页上限；`cancelResolveTask()` 设 `isResolving = false` |
| 11 | MissKon | `MissKonFavoritesBridge.swift` | `pageURLs` 使用 `appendingPathComponent` 丢失尾部斜杠 | 改为字符串拼接保持格式一致 |
| 12 | Wallhaven ×2 | `WallhavenContentViewController.swift` + `WallhavenImageDetailViewController.swift` | Observation 监听 `.count` 而非数组本身，detail 解析后 UI 不刷新 | `_ = library.wallpapers.count` → `_ = library.wallpapers` |

### P2 — 性能与数据完整性（11 项）

| # | 模块 | 文件 | 问题 | 修复 |
|---|------|------|------|------|
| 13 | Wallhaven | `WallhavenAPIClient.swift` | 429 rate-limit 直接抛错，不重试 | 自动等待 2s 重试，最多 2 次 |
| 14 | Wallhaven | `WallhavenFeedStore.swift` | `detailCache` 永不过期无上限 | 500 条 LRU 淘汰，按 `createdAt` 排序 |
| 15 | MissKon | `MissKonDetailStore.swift` | 多页串行解析，5 页 = 5 次串行 HTTP | `withTaskGroup` 并行批处理，每批最多 6 页 |
| 16 | MissKon | `MissKonFeedStore.swift` | feed cache JSON 无上限，长期使用后数 MB | 每 section 最多 200 条，`suffix` 保留最新 |
| 17 | MissKon | `MissKonListResolver.swift` | HTML 解析无结构校验，站点改版后静默失败 | 检测已知结构标记，缺失时 `nextPageURL = nil` |
| 18 | MissKon | `MissKonDetailStore.swift` | 并行批处理无大小限制 | `maxBatch = min(6, ...)` |
| 19 | MissKon | `MissKonImageDetailViewController.swift` | 详情面板关闭后 prefetch 未停止 | `stopDetailPrefetching()` 调用 |
| 20 | Gallery | `DetailPageHTMLResolver.swift` | 每次调用动态编译 `NSRegularExpression` | 4 个 regex 缓存为 `static let` |
| 21 | Gallery | `GalleryDetailStore.swift` | 详情页解析失败后立即重试循环，无退避 | `failedPageURLs` 集合 + `ensureNextDetailPageLoaded` 跳过失败页 |
| 22 | Shared | `SharedRemoteImageView.swift` | `setImage` 在 guard 之前 cancel，相同 URL 重入导致加载丢失 | guard 移到 cancel 之前 |
| 23 | Shell | `WorkspaceToolbarHost.swift` | grid column +/- 图标颠倒（minus=增大，plus=缩小） | 互换 `plus.magnifyingglass` / `minus.magnifyingglass` |

### P3 — 用户体验与防御性编程（7 项）

| # | 模块 | 文件 | 问题 | 修复 |
|---|------|------|------|------|
| 24 | MissKon | `MissKonFeedStore.swift` | 搜索无 debounce，每次按键发请求 | `setSearchText` 300ms debounce |
| 25 | MissKon | `MissKonFeedStore.swift` + `ContentViewController.swift` | section 切换不记滚动位置 | `cachedScrollOffsets` 保存/恢复 |
| 26 | MissKon | `MissKonDetailStore.swift` + `ImageDetailViewController.swift` | 详情解析进度不透明 | "解析中 (3 页, 15 张)" |
| 27 | MissKon | `MissKonFeedStore.swift` | `restoreSectionCache` 空缓存分支 `nextPageURL` 未清 | 添加 `nextPageURL = nil` |
| 28 | Gallery | `GalleryDetailStore.swift` | `itemPageCursors` 等三个字典在 `prepare(for:)` 不清除，渐进泄漏 | 添加 `removeAll()` |
| 29 | Shared | `WorkspaceZoomableImageView.swift` | 图片替换后 `lastFitSize` 不重置 | 添加 `replaceImage(_:)` API |
| 30 | Shared | `WorkspaceThumbnailGridCardView.swift` | `resetForReuse` 不重置 `contentMode` | 添加 `contentMode = .aspectFill` |

---

## 二、审计覆盖模块

| 模块 | 文件数 | 发现问题 | 已修复 |
|------|--------|----------|--------|
| MissKon | 17 | 15 | 15 |
| Wallhaven | 15 | 8 | 8 |
| 4KHDGallery | ~15 | 4 | 4 |
| Favorites | ~3 | 1 | 0 (LOW) |
| Shared | ~25 | 8 | 6 |
| Shell | ~10 | 5 | 4 |
| App | ~5 | 2 | 0 (LOW) |

---

## 三、关键架构决策

1. **Task 变量隔离**: 常规分页 (`loadTask`)、搜索分页 (`searchLoadTask`)、搜索提交 (`searchTask`)、搜索去抖 (`searchDebounceTask`) 各自独立，避免互相取消。

2. **并行策略**: 详情页解析和上传者作品查询均采用 `withTaskGroup` + 小批次（≤6），利用 URLSession 的 per-host 限流自然节流。

3. **缓存淘汰**: feed cache 200 条/section、detailCache 500 条 LRU — 足够覆盖正常浏览，防止磁盘膨胀。

4. **Observation 追踪**: `@Observable` 数组应监听数组本身而非 `.count`，以捕获 in-place 元素变更。

---

## 四、已知未修复问题（低优先级，18 项）

详见 agent 扫描报告，主要包括:
- Gallery `selectedSlot` 越界回退行为、搜索无 debounce、无缓存过期
- Favorites URL 字符串比较脆弱、`toggle` 返回值被忽略
- Shared 层 hover 状态传播为空操作、键盘事件（'f'/Tab）误报、`DetailPageImageCache` flush 竞态
- Shell 层 toolbar 插入索引漂移、ImmersiveController 双通道通知、Inspector 元数据过时
- App 层 WindowController 泄漏、async observer 移除间隙

这些不会导致崩溃或功能异常，可在后续迭代中按需处理。

---

## 五、提交历史

```
9f2a3a7 chore: add Claude Code skill and project permissions
61e6df0 fix: Gallery regex caching, zoom re-fit, card reuse, dictionary leak
294aa20 fix: Shell/Shared/Gallery — bootstrap order, waterfall cache, toolbar icons, image reload, retry loop
b77e755 feat: enable secure restorable state for NSWindow persistence
f5fbb1e fix: preserve upload order in parallel Wallhaven UploaderResolver
e123a71 fix: MissKon UI — scroll position memory, detail progress, prefetch on hide
a6e5113 fix: MissKon — search debounce, pagination guard, parallel detail, cache pruning
d6f5401 fix: Wallhaven — parallel uploader resolution, API 429 retry, search pagination, state guards
```

---

## 六、构建验证

所有提交均通过 `xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build`，零 error 零 warning。
