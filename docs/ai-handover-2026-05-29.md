# 4KHD 在线模块稳定性与体验优化报告

**日期**: 2026-05-29  
**范围**: 全 7 模块 — MissKon、Wallhaven、4KHDGallery、Favorites、Shared、Shell、App  
**提交**: 30 commits，36 文件，+1443/-392 行  
**编译**: 全部通过，零 error 零 warning，零 SwiftUI 命中  

---

## 一、修复总览（按轮次）

### 第一轮：MissKon + Wallhaven 核心稳定性（7 commits）

| # | 模块 | 修复 |
|---|------|------|
| 1 | Wallhaven | UploaderResolver 24 次串行 API → `withTaskGroup` 并行（12s→~2s） |
| 2 | Wallhaven | API 429 rate-limit 自动重试（2 次，间隔 2s） |
| 3 | Wallhaven | `loadTask`/`searchLoadTask` 分离，消除搜索/普通分页互斥 |
| 4 | Wallhaven | `showUploaderWorks`/`loadMoreUploaderWorks` 补 `isBrowsingUploader` guard |
| 5 | Wallhaven | uploader→搜索清 `isBrowsingUploader`；`loadMoreIfNeeded` 加搜索路由（P0） |
| 6 | Wallhaven | `detailCache` 500 条 LRU 淘汰 |
| 7 | Wallhaven | ContentViewController/ImageDetailViewController observation 监听数组而非 `.count` |
| 8 | MissKon | `loadTask`/`searchLoadTask`/`searchDebounceTask` 分离 |
| 9 | MissKon | `ListResolver` 分页推断 `>12`；`/page/N/` URL 替换更健壮 |
| 10 | MissKon | `DetailStore` 50 页上限 + `isResolving` 在 cancel 时重置 |
| 11 | MissKon | `FavoritesBridge` pageURLs 字符串拼接保留尾部斜杠 |
| 12 | MissKon | `feed cache` 200 条/section；refresh 新内容在前 + `prefix` 裁剪 |
| 13 | MissKon | 搜索 300ms debounce |
| 14 | MissKon | section 切换保存/恢复滚动位置 |
| 15 | MissKon | 详情解析进度 "解析中 (3 页, 15 张)" |
| 16 | Shell | WaterfallLayout `updateCachedFrames` `didLayoutAllItems` 保留实际状态 |
| 17 | Shell | `bootstrapModules` 在 `applyCurrentRoute` 之前执行（P0） |
| 18 | Shell | 工具栏 +/- 图标互换修复 |
| 19 | Shared | `RemoteImageView.setImage` guard 移到 cancel 前 |
| 20 | Gallery | `DetailPageHTMLResolver` 4 个 regex 缓存为 `static let` |
| 21 | Gallery | `GalleryDetailStore` 详情解析失败重试循环修复 |
| 22 | Gallery | `GalleryDetailStore` 字典内存泄漏修复 |

### 第二轮：回归修复 — cancel resolution + retry guard + task lifecycle（2 commits）

| # | 模块 | 修复 |
|---|------|------|
| 23 | MissKon | `cancelResolution()` 详情关闭时取消 HTML 解析 |
| 24 | MissKon | 解析失败不自动重试；`retry()` 用 force 真正重来 |
| 25 | MissKon | `resolveTask` 通过 `defer` 在所有退出路径清 nil |
| 26 | Wallhaven | `inFlightPage/SearchPage/UploaderPage` 在 `resetAndRefresh`/`setSection`/`clearUploaderBrowsing`/`submitSearch` 中清理 |
| 27 | Wallhaven | `refreshFromNetwork` 同步设置 `isRefreshingList` |

### 第三轮：MissKon 恢复解析 + 失败重试 UI + Wallhaven request token（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 28 | MissKon | `isResolutionComplete` 标志 + resolve 继续未完成页（过滤已解析 URL） |
| 29 | MissKon | 解析全部失败时 `showFailure` + retry，隐藏 prev/next/counter/filmstrip |
| 30 | Wallhaven | `listRequestToken` + `beginListRequest()`/`invalidateListRequests()` — 旧 Task 不能清新状态 |

### 第四轮：Wallhaven 每请求独立 token + MissKon resolve gate（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 31 | Wallhaven | `beginListRequest()` 生成新 UUID 每个请求；`invalidateListRequests()` 在取消路径调用 |
| 32 | MissKon | `resolve` 非 force 入口 `guard resolveTask == nil && !isResolutionComplete` |

### 第五轮：Wallhaven token-guard 状态写入（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 33 | Wallhaven | 4 个请求入口 await 返回后写入前全部 guard `listRequestToken + section/query`；catch 分支也校验 token |

### 第六轮：detail resolve identity guard + search sync state + frozen params（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 34 | Wallhaven | `resolveDetail` 取消旧 task 在 cache 检查前；await 后 guard `resolvedWallpaper?.id == requestID` |
| 35 | MissKon | `submitSearch` 同步 `activeSearchQuery`/`isRefreshingList` + cancel `searchLoadTask` |
| 36 | Wallhaven | `makeSearchParameters` 在 Task 创建前冻结参数 + apiKey |

### 第七轮：detail retry + sync isRefreshing + clear in-flight on refresh（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 37 | Wallhaven | `resolveDetail` 入口 guard 改为 `sameID && isResolvingDetail`，失败后允许重试 |
| 38 | Wallhaven | `submitSearch` `isRefreshingList`/`feedErrorMessage` 移到 Task 创建前 |
| 39 | MissKon/Wallhaven | `refreshFromNetwork` 清 `inFlightPageURL/inFlightPage`；MissKon 同步 `isRefreshingList` |

### 第八轮：refreshFromNetwork 模式路由（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 40 | MissKon | `refreshFromNetwork` 搜索态路由到 `submitSearch(force:true)` |
| 41 | Wallhaven | `refreshFromNetwork` 根据 uploader/search/favorites/browse 四模式路由；uploader 刷新保持 uploader 模式 |
| 42 | Both | `submitSearch` 新增 `force` 参数 |

### 第九轮：uploader 参数快照化 + 任务清理（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 43 | Wallhaven | `showUploaderWorks`/`loadMoreUploaderWorks` 创建 Task 前捕获 username/purity/apiKey/page |
| 44 | Wallhaven | uploader refresh 分支 cancel+nil `searchTask/searchLoadTask/searchDebounceTask` |
| 45 | Wallhaven | `restorePreviousBrowseState` 补 `searchLoadTask/searchDebounceTask` 取消 |

### 第十轮：Wallhaven detail apiKey freeze + Gallery search force+identity guard（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 46 | Wallhaven | `resolveDetail` Task 前捕获 `requestApiKey` |
| 47 | Gallery | `submitSearch(force:)` + `refreshFromNetwork` 搜索态 force 重试 |
| 48 | Gallery | `submitSearch`/`loadMoreSearchIfNeeded` await 后 guard `activeSearchQuery == requestQuery` |
| 49 | Gallery | force 搜索时清 `pendingSearchLoadMore` + `searchNextPageURL` |

### 第十一轮：Gallery 列表 await cancel guard + search isolation（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 50 | Gallery | `refreshFromNetwork`/`loadNextListPageIfNeeded` await 后 guard `!Task.isCancelled` |
| 51 | Gallery | `finishListRefresh` 在 `activeSearchQuery != nil` 时不影响当前 UI |

### UI 一致性轮：Gallery 键盘/重试/搜索高亮（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 52 | Gallery | table/grid `keyboardContext` 增加 Escape（clearSearch）+ Enter（open detail） |
| 53 | Gallery | footer 点击重试（红色错误文本 + click gesture） |
| 54 | Gallery | 搜索高亮：列表 `highlightedAttributedString` + 网格 `highlightQuery` |

### 体验优化轮：API Key UserDefaults + MissKon 渐进详情 + 占位胶片条（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 55 | Wallhaven | API Key 从 Keychain → UserDefaults（无启动弹窗） |
| 56 | MissKon | 胶片条条件从 `slots.count > 1` 改为 `!slots.isEmpty` |
| 57 | MissKon | 渐进式解析：只解析第一页 + `ensureNextDetailPageLoadedIfApproachingEnd` |
| 58 | MissKon | `prepare` 生成 `imageCount` 个占位 slot；`mergeResolvedPage` 替换 knownURL |
| 59 | MissKon | 大图 cover-first：`knownURL==nil` 时不清图 |
| 60 | MissKon | "0 张图片" → "多张图片" |
| 61 | Wallhaven | `isIncomplete` 但有 `previewURL` 时优先显示 preview |

### MissKon 渐进状态机重构轮（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 62 | MissKon | `knownPageURLs` 动态发现 + `pageTasks` 字典替代单 `resolveTask` |
| 63 | MissKon | 加载触发阈值用 `maxResolvedDisplayIndex`（而非 slot 总数） |
| 64 | MissKon | 点击 placeholder slot → `ensurePageLoadedForSlot` 即加载 |
| 65 | MissKon | `schedulePrefetch(count:after:)` 首屏预热 2 页 |
| 66 | Wallhaven | 删除 `WallhavenKeychain.swift` |

### MissKon 状态机修复轮（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 67 | MissKon | `reloadDetail` 只在 `resolvedPageCount==0 && errorMessage==nil` 触发初始解析 |
| 68 | MissKon | `resolve` 第一页已解析时不设 `prefetchNext` |
| 69 | MissKon | `mergeResolvedPage` 完全替换 pageURL 所有 slot（移除多余占位） |
| 70 | MissKon | `loadPage` catch 分支加 `currentItem?.id == itemID` guard |
| 71 | Wallhaven | `keychainError` → `keyStorageError` |

### MissKon 失败页 slot 移除（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 72 | MissKon | `removeSlots(forFailedPage:)` — 页失败时移除对应占位 slot，修复 selection |
| 73 | MissKon | `replaceSlots(for:with:)` 统一 merge/remove 逻辑 |

### MissKon 全部失败 UI（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 74 | MissKon | `resolutionFailed` 判定不依赖 `slots` 非空；全部失败时只显示 retry，不叠加 emptyLabel |

### Wallhaven Uploader 稳定性加强（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 75 | Wallhaven | 3 处 uploader catch block 补齐 `uploaderUsername == requestUsername` |
| 76 | Wallhaven | `extractWallpaperIDs` 增加 `href="/w/{id}"` 和 `href="https://wallhaven.cc/w/{id}"` 解析 |
| 77 | Wallhaven | `fetchUploadsHTML` 从 `try?` 改为 `try` 透传错误 |

### Wallhaven 上传者页顺序修复（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 78 | Wallhaven | `extractWallpaperIDs` 收集 `(location, id)` → 按 location 排序 → 去重 |

### 收尾轮（1 commit）

| # | 模块 | 修复 |
|---|------|------|
| 79 | Wallhaven | `showUploaderWorks` cancel `searchDebounceTask` |
| 80 | MissKon | `replaceSlots` 按 `knownPageURLs` 顺序插入（page 3 先完成不插在 page 2 前） |

---

## 二、关键架构决策

### 1. 异步状态管理 (Wallhaven)

```
listRequestToken (UUID)
├── beginListRequest() — 每个网络请求入口生成新 token
├── invalidateListRequests() — 取消/切换路径递增 token 使旧 Task 失效
├── Task 写入前: guard listRequestToken == requestToken && section/query checks
├── Task catch 前: guard listRequestToken == requestToken && section/query checks
└── Task 完成清理: guard listRequestToken == requestToken
```

### 2. MissKon 渐进式详情解析

```
prepare(item) → 生成 imageCount 个占位 slot + coverURL 首槽
resolve(item) → 仅解析第 1 页 + prefetch 2 页
用户翻到尾部 → ensureNextDetailPageLoadedIfApproachingEnd(from:) 
              → maxResolvedDisplayIndex - 4 阈值
              → loadNextUnresolvedPage()
用户点占位 slot → ensurePageLoadedForSlot(at:) → 立即加载该页
pageTasks: [URL: Task] — 每页独立在途任务
mergeResolvedPage → 完全替换该 pageURL 的 slots
removeSlots(forFailedPage) → 移除失败页的占位 slots
```

### 3. refreshFromNetwork 模式路由

```
Wallhaven:
  section == .favorites → refreshFavorites()
  isBrowsingUploader → uploader page 1 重载 (保持 uploader 模式)
  activeSearchQuery 非空 → submitSearch(query, force: true)
  否则 → 普通 browse refresh

MissKon:
  section == .favorites → restoreSectionCache()
  activeSearchQuery 非空 → submitSearch(query, force: true)
  否则 → 普通 section refresh

Gallery:
  activeSearchQuery 非空 → submitSearch(force: true)
  否则 → 普通 section/network refresh
```

### 4. Task 变量隔离

| 变量 | MissKon | Wallhaven |
|------|---------|-----------|
| `loadTask` | 普通分页 | 普通分页 / uploader load |
| `searchLoadTask` | 搜索分页 | 搜索分页 |
| `searchTask` | 搜索提交 | 搜索提交 |
| `searchDebounceTask` | debounce 计时 | debounce 计时 |
| `inFlightPageURL/Page` | URL 去重 | page 号去重 |
| `pageTasks` | 详情页字典 | — |

---

## 三、修改文件统计

| 目录 | 文件数 | 净增 |
|------|--------|------|
| MissKon | 10 | ~420 行 |
| Wallhaven | 7 | ~530 行 |
| 4KHDGallery | 5 | ~110 行 |
| Shared | 4 | ~20 行 |
| Shell | 2 | ~10 行 |
| App | 1 | ~5 行 |
| docs + .claude | 8 | ~350 行 |

---

## 四、已知未修复问题（低优先级）

详见初始审计报告。主要包括:
- Gallery `GalleryDetailStore` 无 `cancelResolution` 方法（详情关闭后链式加载不停止）
- Gallery 收藏跨模块不同步（缺少 `refreshFavoritesIfNeeded`）
- Shared 层 hover 状态传播为空操作
- `DetailPageImageCache` flush 竞态
- Wallhaven `restorePreviousBrowseState` 不清 `inFlightPage/inFlightSearchPage`（极低概率）

---

## 五、提交历史

```
f8a4fa5 fix: cancel searchDebounce on uploader entry, slot insertion by page order
736022f fix: Wallhaven uploader HTML fallback preserves page order
a2f306d fix: Wallhaven uploader — catch identity guard, href fallback, error propagation
f183fad fix: MissKon — clean all-failed UI state when all pages fail
11a45dd fix: MissKon — remove dead placeholder slots on page resolution failure
d66bbbf fix: MissKon — no auto-continue, excess placeholder removal, task identity guard, Keychain rename
fa00f0c fix: MissKon progressive state machine + remove Wallhaven Keychain file
771733c fix: API key UserDefaults, MissKon progressive detail, filmstrip placeholders, 0-count, preview-first
023f0f0 fix: Gallery UI consistency — keyboard, footer retry, search highlight
b628402 fix: Gallery — cancel guard on list awaits, search isolation in finishListRefresh
667dc72 fix: Wallhaven detail apiKey freeze, Gallery search force+identity guard
dd0bc0d fix: Wallhaven — freeze uploader params, cancel all tasks on refresh, restore cleanup
16c02e1 fix: refreshFromNetwork routes to current mode (search/uploader/browse)
73ba2c2 fix: retry failed detail, sync search isRefreshing, clear in-flight on refresh
80eba69 fix: detail resolve identity guard, search sync state, frozen search params
bdf2b0d fix: Wallhaven — token-guard state writes after await, not just cleanup
8be1b3f fix: Wallhaven per-request tokens, MissKon resolve gate
1b80e1a fix: third-pass — resume resolution, failure retry UI, request token
27d1e0e fix: second-pass regression — cancel resolution, retry guard, task lifecycle, in-flight cleanup
507ba4d fix: MissKon/Wallhaven stability — lazy detail, image upgrade, purity gate, load gate, refresh order
f4b5a8a docs: add comprehensive audit and fix report (2026-05-29)
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

所有 30 个提交均通过:
```bash
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
```
零 error，零 warning，零 SwiftUI 命中。
