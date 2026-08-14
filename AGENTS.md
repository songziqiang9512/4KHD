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
    UI/           — 瀑布流布局、缩略图卡片、缩放图片视图、RemoteImageView、缩略图预取控制器
      Detail/       — 详情区覆盖层组件
  Modules/      — 业务模块实现
    4KHDGallery/  — 4KHD.com 在线图库模块
    LocalLibrary/ — 本地图片模块
    Favorites/   — 收藏记录模块
    MissKon/     — misskon.com 在线图库模块
    Wallhaven/   — wallhaven.cc 在线壁纸模块
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
| 收藏 | `Favorites` | 统一收藏入口：跨模块汇总（4KHD/MissKon/Wallhaven），按来源筛选，列表/网格 + 信息卡详情，独立于业务模块 |

## 4. 共享能力清单

| 组件 | 路径 | 用途 |
|------|------|------|
| `WorkspaceTableView` | `Shared/UI/` | 统一 NSTableView 基类（menu、keyDown、live resize） |
| `WorkspaceCollectionView` | `Shared/UI/` | 统一 NSCollectionView 基类（hover、tracking area、keyDown） |
| `WorkspaceZoomableImageView` | `Shared/UI/` | 可缩放图片视图基类（pinch zoom、fit、reset） |
| `WorkspaceThumbnailWaterfallLayout` | `Shared/UI/` | 瀑布流布局 |
| `WorkspaceThumbnailGridCardView` | `Shared/UI/` | 缩略图卡片视图（图片+文字+高亮+hover） |
| `WorkspaceThumbnailPrefetchController` | `Shared/UI/` | 缩略图预取调度器（可见区附近智能预取） |
| `RemoteImageView` | `Shared/UI/` | 共享远程图片视图（Nuke 加载、占位符、aspectFill/Fit、同步缓存命中） |
| `DetailOverlayChromeView` | `Shared/UI/Detail/` | 详情区覆盖层圆角背景 |
| `DetailNavigationButton` | `Shared/UI/Detail/` | 详情区导航按钮（圆形毛玻璃） |
| `RemoteImagePipeline` | `Shared/Services/` | Nuke 图片加载管线（含 thumbnailPrefetcher + detailPrefetcher 分离） |
| `DetailPageImageCache` | `Shared/Services/` | 详情页图片 URL 缓存（7 天过期，500/800 容量限制） |
| `SharingPresenter` | `Shared/Platform/` | 系统分享面板弹出 |
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

### 统一收藏模块（在线收藏）

- 侧边栏「在线收藏」是「本地」分组内的子节点（紧跟「我的图片」），工具栏按来源筛选（全部/4KHD/MissKon/Wallhaven，rawValue 作路由 itemID）
- 交互与 MissKon/4KHD 完全一致：瀑布流网格（共享 `WorkspaceThumbnailWaterfallLayout` + `WorkspaceThumbnailGridCardView`，间距 8/10/12）、列表行、单击选中/双击开详情、hover 高亮、方向键、右键菜单、搜索高亮、列数调整
- 详情区是大图查看区（缩放/上张下张/计数/胶片条/沉浸模式），由 `FavoritesDetailStore` 统一 slot 模型驱动：Gallery 记录走 `DetailPageHTMLResolver`、MissKon 记录走 `MissKonDetailResolver` 渐进解析，Wallhaven 记录单图（封面）
- **来源判定必须用 detailURL host**（`FavoriteSource.source(for:)`），`FavoriteRecord.sourceID` 不可靠；封面/大图加载必须按来源设置 `imageRequestConfigurator`（各模块防盗链 Referer）
- 模块 UI 直接观察 `FavoritesStore.favorites`（`FavoritesModuleStore.visibleRecords` 是计算属性），不要加回 `onFavoritesChanged` 链路
- Gallery/MissKon 来源的收藏项支持「保存整个图集」和「保存当前图片」；Wallhaven 收藏项无图集下载

### MissKon 模块

- 核心链路完整：列表/网格、分页、搜索高亮+debounce、收藏、Inspector、磁盘列表缓存
- **渐进式详情加载**：`prepare(item:)` 生成占位 slot → `resolve(item:)` 仅加载第一页 + 预取 2 页 → 用户翻到尾部触发 `ensureNextDetailPageLoadedIfApproachingEnd` → 按需加载后续页
- **胶片条占位**：`imageCount > 0` 时预生成精确数量占位 slot；页面解析后 `mergeResolvedPage` 替换 knownURL
- **失败页处理**：失败页占位 slot 自动移除；全部失败显示"解析失败"重试按钮
- **分页阈值**：fallback 猜测使用 `articleCount > 12`（top30 等无显式分页标签）
- **缓存修复**：`restoreSectionCache` 在 `cachedNextPageURLs[section] == nil` 时自动触发刷新
- **详情区封面优先**：打开详情时查 Nuke 内存缓存（4096px → 512px 回退），命中直接显示不闪烁

### Wallhaven 模块

- API Key 存储改用 **UserDefaults**（原 Keychain 已移除，避免每次启动弹授权窗）
- **列表请求状态机**：`beginListRequest()` 每请求独立 token → await 后写入前 guard `listRequestToken + section/query` → 旧 Task 不能清新状态
- **上传者浏览**：参数快照化（username/purity/apiKey 在 Task 创建前捕获）→ 身份校验（`uploaderUsername == requestUsername`）→ HTML fallback 支持 `data-wallpaper-id` + `href="/w/{id}"`
- **refresh 模式路由**：`refreshFromNetwork` 自动判断当前模式（uploader/search/favorites/browse）并路由到正确的刷新路径
- **工具栏**：独立 `onlineSave`/`onlineInfo` 按钮（与 Wallhaven 布局统一），+/- 图标交换（minus=更多列=缩小）
- **详情区封面优先**：`setImageURL` 同步查 Nuke 缓存，命中直接显示

### 4KHDGallery 模块（参考实现）

- 在线模块参考实现；网格列数 2-6、列表/网格切换保留位置
- **工具栏**：独立保存/信息按钮（`onlineSave`/`onlineInfo`），与 Wallhaven 布局对齐
- **键盘交互**：Escape 清搜索、Enter 打开详情
- **底部重试**：footer 点击重试，错误显示红色 "errorMessage — 点击重试"
- **搜索高亮**：列表/网格均支持 `activeSearchQuery` 高亮
- **收藏下一张按钮**：`imageCount == 0` 时回退用 `loadedImageSlots.count` 判断

### 设置面板

- **布局**：一个统一切换选项同时控制 4KHD/MissKon/Wallhaven/本地图库四个模块的列表/网格
- **缓存上限**：在线缓存容量选择（512MB-4GB/无限制）
- **清除缓存**：一键清除 Nuke 图片缓存、详情页缓存、MissKon/Wallhaven 模块缓存、本地缩略图缓存、临时文件
- **侧边栏**：开关控制 4KHD/MissKon 模块显示
- 全部中文化

### 全局约束

- 修改 Shell 集成任何模块时，先搜索 `case .模块名` 覆盖所有 switch
- 修改任何在线模块时，以 `4KHDGallery` 的状态流和 UI 行为为参考
- 在线模块异步结果必须按请求时的 section/query 回写，不能在 `await` 后直接读当前 section 写状态
- 收藏桥和详情图片解析必须使用 exact/subdomain allowlist，不要用 `host.contains(...)`
- 详情 HTML 截取不要用 `lowercased()` 产生的 `String.Index` 切原字符串；用 `NSString`/`NSRange` 或原字符串 case-insensitive range
- 当前 Xcode 工程包含 `4KHD` App target 和 `4KHDTests` XCTest target；纯逻辑与共享命令行为优先补回归测试
- 在线模块通过 `WorkspaceModuleRegistry.bootstrapModule(_:)` 在首次进入时启动；不要恢复为启动阶段全模块并发刷新
- 在线图片只使用 Nuke DataCache 作为磁盘层，URLCache 不落盘；缓存清理必须同时清内存状态与对应磁盘目录
- **生产代码 0 SwiftUI** — 不得引入 `import SwiftUI`、`NSHostingController`、`NSViewRepresentable`、`AnyView`
- 分页 `nextPageURL` 永远直接用 `page.nextPageURL`，不要加 `newItems.isEmpty ? nil : ...` 条件

常用验证：

```bash
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
```
