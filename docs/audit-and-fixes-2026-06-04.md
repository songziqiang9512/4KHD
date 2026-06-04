# 4KHD 代码审计与修复报告

**日期**：2026-06-04
**分支**：`main`
**编译状态**：✅ BUILD SUCCEEDED

---

## 一、审计概览

对 4KHD 项目 **131 个 Swift 文件、24,533 行代码** 进行了全量审计，聚焦两个维度：

1. **代码膨胀**：可以用更少代码实现的功能
2. **Apple 开发规范**：AppKit/Swift 最佳实践合规性

### 发现汇总

| 类别 | 严重 (🔴) | 重要 (🟠) | 中等 (🟡) |
|------|-----------|-----------|-----------|
| 代码膨胀 | 2 处 | 1 处 | 3 处 |
| Apple 规范违规 | 2 处 | 3 处 | 3 处 |

---

## 二、已修复问题（4 个提交）

### 🔴 严重：`try!` 强制解包 — 潜在崩溃

**文件**：`4KHD/Modules/4KHDGallery/Services/DetailPageHTMLResolver.swift:127-142`

4 个正则表达式全部使用 `try!`。如果正则模式有语法错误，应用直接崩溃。

**修复**：改为 `do/catch` + `assertionFailure`（Debug 模式下报警）+ 无害 fallback regex（`"$^"` 匹配空）：
```swift
// Before
private nonisolated static let urlExtractionRegex = try! NSRegularExpression(...)

// After
private nonisolated static let urlExtractionRegex: NSRegularExpression = {
    do { return try NSRegularExpression(...) }
    catch {
        assertionFailure("Invalid urlExtractionRegex: \(error)")
        return DetailPageHTMLResolver.noMatchRegex
    }
}()
```

### 🔴 严重：`NSImage(systemSymbolName:)` 强制解包

**文件**：`WallhavenImageDetailViewController.swift:42`

```swift
// Before: 符号名不可用时崩溃
NSImage(systemSymbolName: "photo.on.rectangle", ...)!

// After: 提供空白占位图作为降级
NSImage(systemSymbolName: "photo.on.rectangle", ...)
    ?? NSImage(size: NSSize(width: 16, height: 16))
```

### 🟠 重要：`UserDefaults` 存储大量数据

**文件**：`FavoritesStore.swift`

收藏列表（可达数百条记录）全部存入 `UserDefaults`，违反 Apple 规范（UserDefaults 仅用于小型偏好值）。

**修复**：
- 迁移到 `Application Support/4KHD/favorites.json` 文件存储
- 首次加载时自动从 UserDefaults 迁移旧数据，然后删除旧 key
- 向后兼容，用户无感知

### 🟠 重要：`viewDidAppear` 抢夺 First Responder

**文件**：4 个 DetailViewController（Gallery / MissKon / Wallhaven / LocalLibrary）

每个详情视图控制器在 `viewDidAppear` 中无条件抢夺 first responder，导致用户在搜索框中输入时被意外抢走焦点。

**修复**：添加 `hasAppeared` 守卫 + 改用 `makeFirstResponderUnlessDescendantIsFirstResponder`：
```swift
override func viewDidAppear() {
    super.viewDidAppear()
    guard !hasAppeared else { return }  // 仅首次
    hasAppeared = true
    if let fr = view.window?.firstResponder as? NSText, fr.isEditable { return }
    view.window?.makeFirstResponderUnlessDescendantIsFirstResponder(view)
}
```

### 🟡 代码膨胀：WorkspaceToolbarHost switch 四路重复

**文件**：`WorkspaceToolbarHost.swift` — **1200 → 1032 行 (-168 行, -14%)**

12 个方法中，每个都执行相同的四路 switch（gallery/local/missKon/wallhaven），99% 的分支做完全相同的事。

**修复**：在 `WorkspaceToolbarSnapshot` 上添加 `CommonFields` 结构体和 `fields` 计算属性，将 12 个方法的四路 switch 全部替换为单行字段访问：
```swift
// Before (每个地方都这样写，共12处)
switch snapshot {
case .gallery(let s): refreshItem.isEnabled = !s.isRefreshing
case .local(let s):   refreshItem.isEnabled = !s.isRefreshing && s.hasSelection
case .missKon(let s): refreshItem.isEnabled = !s.isRefreshing
case .wallhaven(let s): refreshItem.isEnabled = !s.isRefreshing
}

// After (一处定义，12处使用)
let f = snapshot.fields
refreshItem.isEnabled = !f.isRefreshing && (moduleID != .local || f.hasSelection)
```

### 🟡 代码膨胀：FeedStore 样板代码

**文件**：`WallhavenFeedStore.swift` — **846 → 815 行 (-31 行)**

10+ 处重复的任务取消代码（4-6 行每处）。

**修复**：提取 `cancelAllTasks()` 和 `resetInFlightMarkers()` 辅助方法。

**附加修复**：
- `MissKonFeedStore`：删除无用的 `saveCacheIfNeeded()` 包装方法（仅 2 行，已在所有 4 个调用处内联）
- `WorkspaceStoragePreferencesViewController`：`DateFormatter` 从每次创建改为 `static let` 复用

---

## 三、未修复问题（需专项处理）

以下问题需要更大范围的架构改动，建议单独 PR：

### 1. Gallery / MissKon / Wallhaven 三模块并行重复（~4500 行）

三个在线模块有结构几乎相同的文件，核心的 NSCollectionView 数据源/代理、瀑布流布局、缩略图预取逻辑是三份几乎相同的代码：

| 文件类型 | Gallery | MissKon | Wallhaven | 合计 |
|----------|---------|---------|-----------|------|
| GridContainerView | 818行 | 466行 | 454行 | 1738行 |
| ContentViewController | 652行 | 426行 | 391行 | 1469行 |
| ImageDetailViewController | 391行 | 389行 | 615行 | 1395行 |

**建议**：创建泛型基类 `OnlineGridContainerView<Item: OnlineImageItem>`，各模块提供差异化闭包。

### 2. WallhavenFeedStore 6 个异步加载方法

`refreshFromNetwork`、`loadMoreIfNeeded`、`submitSearch`、`loadMoreSearchIfNeeded`、`showUploaderWorks`、`loadMoreUploaderWorks` 共享相同的 Task/取消/分页/状态更新模板。但每个方法的 API 调用源、分页逻辑、token 验证条件不同，强行合并有回归风险。

**建议**：提取一个通用的 `PaginatedLoader<Source>` 类型，将数据源差异参数化。

### 3. 内容视图缺少 VoiceOver 无障碍标签

缩略图卡片、图片查看器、Filmstrip 缩略图条缺少 `accessibilityLabel` 和 `accessibilityRole`。

### 4. `withObservationTracking` 模式

12 处使用 `withObservationTracking`，在 `onChange` 中递归重注册。在当前代码中不会出问题，但存在潜在无限递归的风险（如果任一被观察属性的变更触发了另一个属性的变更）。

---

## 四、本轮完整提交历史

```
b025aba fix: remove dead saveCacheIfNeeded wrapper, reuse DateFormatter
8c89ee6 refactor: extract cancelAllTasks/resetInFlightMarkers helpers in WallhavenFeedStore
757fd39 refactor: eliminate WorkspaceToolbarHost switch-on-module duplication
419abf2 fix: address critical audit issues — crash risks and Apple guidelines
59cbe3f feat: add favorites import/export with UI in preferences
b470f77 fix: avoid split view constraint conflicts in immersive mode
```

### 代码量变化

| 指标 | 数值 |
|------|------|
| 修改文件 | 16 |
| 新增代码 | +491 行 |
| 删除代码 | -318 行 |
| 纯重构净减少 | ~199 行 |
| WorkspaceToolbarHost | 1200 → 1032 行 (-14%) |
| WallhavenFeedStore | 846 → 815 行 (-3.7%) |

### 修改范围

```
4KHD/App/
  ├── 4KHDApp.swift                          (参数类型调整)
  ├── WorkspaceAppAssembly.swift             (favoritesStore 注入)
  ├── WorkspacePreferencesWindowController   (收藏导入回调)
  ├── WorkspaceStoragePreferencesVC          (收藏导入/导出 UI + DateFormatter 复用)
  └── WorkspaceToolbarContext.swift          (+CommonFields 结构体)

4KHD/Shell/Toolbar/
  └── WorkspaceToolbarHost.swift             (消除 switch 重复, -168行)

4KHD/Modules/
  ├── 4KHDGallery/
  │   ├── DetailPageHTMLResolver.swift       (try! → do/catch)
  │   ├── FourKHDGalleryStore.swift          (+refreshFavoritesIfNeeded)
  │   └── GalleryImageDetailViewController   (hasAppeared 守卫)
  ├── Favorites/
  │   └── FavoritesStore.swift               (文件存储迁移 + 导入/导出)
  ├── LocalLibrary/
  │   └── LocalImageDetailViewController     (hasAppeared 守卫)
  ├── MissKon/
  │   ├── MissKonFeedStore.swift             (删除死代码包装)
  │   └── MissKonImageDetailViewController   (hasAppeared 守卫)
  └── Wallhaven/
      ├── WallhavenFeedStore.swift           (cancelAllTasks 辅助, -31行)
      └── WallhavenImageDetailViewController (NSImage 降级 + hasAppeared)
```

---

## 五、后续建议

1. **优先**：三模块泛型基类重构 — 单次改动可消除 ~1500 行重复代码
2. **建议**：添加 UI 测试覆盖 toolbar 状态切换和 first responder 行为
3. **可选**：为缩略图卡片添加 VoiceOver 标签，提升可访问性
4. **可选**：将 `withObservationTracking` 递归模式替换为 `observe {}` (iOS 17+/macOS 14+ 新 API)
