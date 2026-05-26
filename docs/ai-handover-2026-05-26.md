# 4KHD 项目 AI 交接文档

> 日期: 2026-05-26 → 更新于 2026-05-27 | 总 Swift 文件: ~120 | 0 SwiftUI | 纯 AppKit

## 1. 项目是什么

macOS 原生图片浏览应用。四个业务模块：在线图库 (4KHDGallery)、在线图库 (MissKon)、本地图片 (LocalLibrary)、收藏 (Favorites)。底壳提供三栏工作区（侧边栏 + 中栏列表/网格 + 右侧详情大图），模块通过 WorkspaceModuleRegistry 插拔。

## 2. 如何最快恢复上下文

1. 读 `AGENTS.md` — 架构、规范、最近完成的工作
2. 读本文件 — 当前状态和待办
3. 读 `docs/misskon-page-structure.md` — MissKon 网站 HTML 结构
4. 打开 Xcode 工程: `open 4KHD.xcodeproj`
5. 构建验证: `xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build`

## 3. 目录结构

```
4KHD/
  App/          — 入口、程序集、工具栏上下文、Inspector
  Shell/        — 工作区底壳、模块路由、侧边栏、工具栏宿主
    Toolbar/    — NSToolbar 实现
    Immersive/  — 窗内大图模式
    WorkspaceLayout/ — 侧边栏展开状态
  Shared/       — 跨模块能力
    Platform/   — 键盘处理、QuickLook、壁纸、CoalescingQueue、AppKit 扩展
    Services/   — RemoteImagePipeline、DetailPageImageCache、CookieBridge
    State/      — WorkspaceDetailPaneController、FilmstripVisibilityController
    UI/         — WorkspaceTableView、WorkspaceCollectionView（共享基类）
                 WorkspaceThumbnailGridCardView、WorkspaceThumbnailWaterfallLayout
                 WorkspaceZoomableImageView（缩放图片基类）
                 SharedRemoteImageView（远程图片加载基类 — 2026-05-27 新增）
                 Detail/ — DetailOverlayChromeView、DetailNavigationButton
  Modules/
    4KHDGallery/ — 4KHD.com 在线图库（Domain/State/Services/UI）
    LocalLibrary/ — 本地图片（Domain/State/Services/UI）
    Favorites/   — 收藏记录（Domain/State）
    MissKon/     — misskon.com 在线图库（Domain/State/Services/UI，16 文件）
  docs/          — misskon-page-structure.md 等文档
```

## 4. 关键设计约束

- **0 SwiftUI**: `rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'` 必须为空
- **模块独立**: 删除任意模块不影响其他模块。模块间不直接 import，只通过 Shared 层共享
- **底壳不依赖模块内部**: Shell 只知道模块 ID 和接入面（WorkspaceModuleDescriptor）
- **50 行能搞定的不写 200 行**: 保持克制
- **macOS 26+, Xcode 26+, Swift 6**
- **SPM 依赖**: 仅 Nuke (图片加载管线)

## 5. 新模块接入模板

参考 `Modules/MissKon/` 的结构：

1. `Domain/` — Section 枚举、Item 结构体、ImageSlot、ResolvedImagePage
2. `Services/` — RequestFactory（HTTP 请求头）、ListResolver（列表页 HTML 解析）、DetailResolver（详情页图片提取）
3. `State/` — FeedStore（列表状态+网络请求）、DetailStore（详情解析状态）、GalleryStore（门面聚合）、ContentPreferences、DetailInteractionController
4. `UI/` — ContentViewController、GridContainerView、ContentViews（列表单元格）、FilmstripView、ImageDetailViewController、RemoteImageView、ZoomableImageView

Shell 集成点（约 12 个文件，搜索 `case .missKon` 找到所有需要添加 case 的 switch 语句）：
- `WorkspaceRoute.swift` — 添加 moduleID case
- `WorkspaceSidebarNode.swift` — 添加 sidebar 节点 case
- `WorkspaceSidebarDataSource.swift` — 添加 sidebar 分组
- `WorkspaceAppContext.swift` — 添加 store 属性
- `WorkspaceAppAssembly.swift` — 创建并注册模块
- `WorkspaceToolbarContext.swift` — 添加工具栏快照和操作 case
- `WorkspaceToolbarHost.swift` — 添加工具栏 UI 更新 case
- `WorkspaceCommandValidator.swift` — 添加命令验证 case
- `WorkspaceShell.swift` — 添加布局/列数切换 case
- `WorkspaceSidebarViewController.swift` — 添加侧边栏选择和图标 case
- `WorkspaceWindowController.swift` — 添加窗口标题 case
- `WorkspaceInspectorWindowController.swift` — 添加 Inspector 刷新 case

## 6. 已完成的工作（截至 2026-05-27）

### MissKon 模块重大完善

- 保存图片、重置缩放、网格列数调整（工具栏 +/-）
- 详情渐进加载（首页先出，后台继续）+ 封面→大图过渡
- 相邻图片预加载
- 翻页修复（标准归档 + top30 特殊模板 /page/N/ 构造）
- 胶片条重写（NSVisualEffectView + DetailOverlayChromeView + 72×96）
- 详情区导航按钮浮层、键盘导航（Escape/Enter/方向键）
- 侧边栏 8 个分类（最新/热门/Cosplay/AI生成/私房摄影/秀人/花漾/收藏）
- 按 section 内存缓存 + 错误重试
- 搜索分页修复、结果去重

### 代码共享

- 提取 `Shared/UI/SharedRemoteImageView.swift`：Gallery 和 MissKon 的 RemoteImageView 从 86/130 行缩减到各 10 行

### 底壳稳定性

- 工具栏增量更新、胶卷条动画、缩放弹回、hover 状态修复等（详见 AGENTS.md 第 7 节）

## 7. 已知问题和待办

### 高优先级
1. **收藏集成** — 收藏是独立模块（Favorites），应在 MissKon 中通过 `FavoritesStore` 桥接，而不是在 MissKon 内部重新实现。需对接 FavoriteSection 的 siteURL
2. **MissKon Inspector** — 当前显示空白占位，需展示当前图片/图集的元信息
3. **详情区重试** — 详情页解析全部失败时，大图区没有重试按钮（仅有状态文字），应添加重试 UI

### 中优先级
4. **搜索高亮** — Gallery 对匹配文字有黄色高亮，MissKon 没有（可在 `MissKonContentViews` 中复用 `highlightedAttributedString`）
5. **缓存持久化** — 当前仅内存缓存，重启丢失。可考虑将已加载的 item 列表写入 UserDefaults/JSON
6. **详情区 RootView** — Gallery 使用 `GalleryImageDetailRootView` 转发 keyDown，MissKon 用普通 NSView，可能丢失部分键盘事件

### 低优先级
7. 封面 aspect ratio 依赖 HTML 中 width/height，不准确时回退到 0.74
8. 项目无单元测试
9. Sparkle 自动更新需通过 Xcode GUI 添加 SPM

## 8. MissKon 模块当前状态（2026-05-27）

### 文件结构（16 文件）

```
MissKon/
  Domain/    MissKonModels.swift        — 8 个 Section + 数据模型
  Services/  MissKonRequestFactory.swift — HTTP 请求头
             MissKonListResolver.swift   — 列表 HTML 解析 + 分页
             MissKonDetailResolver.swift — 详情页图片提取
  State/     MissKonFeedStore.swift      — 列表状态/缓存/搜索/分页
             MissKonDetailStore.swift    — 渐进解析/slot管理
             MissKonGalleryStore.swift   — 门面聚合
             MissKonContentPreferences.swift — 布局+列数偏好
             MissKonDetailInteractionController.swift — 保存/缩放
  UI/        MissKonContentViewController.swift — 中栏(列表+网格)
             MissKonContentViews.swift   — 单元格+footer
             MissKonGridContainerView.swift — 瀑布流网格
             MissKonFilmstripView.swift  — 胶卷条
             MissKonImageDetailViewController.swift — 详情大图
             MissKonRemoteImageView.swift — 远程缩略图(10行wrapper)
             MissKonZoomableImageView.swift — 可缩放图片
```

### 侧边栏分类

| Section | siteURL | 翻页 |
|---------|---------|------|
| latest (最新) | 首页 | ✅ |
| top30 (热门) | /top30/ | ✅ /page/N/ |
| cosplay (Cosplay) | /tag/cosplay/ | ✅ |
| aiGenerated (AI 生成) | /tag/ai-enhanced/ | ✅ |
| privatePhotoshoot (私房摄影) | /tag/private-photoshoot/ | ✅ |
| xiuren (秀人) | /tag/xiuren/ | ✅ |
| huayang (花漾) | /tag/huayang/ | ✅ |
| favorites (收藏) | nil | ❌ |

### Shell 集成验证清单

搜索以下关键字确认所有 switch 已覆盖：
- `case .missKon` 在 Shell/ 和 App/ 中至少出现 14 处
- `MissKonSection` 的 8 个 case 在 WorkspaceSidebarNode 中覆盖
- `WorkspaceToolbarHost` 中：observeState、searchField、refreshItem、filmstripItem、shareItem、gridColumnsControl
- `WorkspaceCommandValidator` 中：adjustGridColumns 等 8+ switch

## 9. 常见编译问题

- 新增模块文件会被 Xcode 自动发现（文件自动发现），无需手动添加到 pbxproj
- 如果 `xcodebuild` 报 SPM 相关错误，清理派生数据: `rm -rf ~/Library/Developer/Xcode/DerivedData/4KHD-*`
- 如果新增 switch case 后编译报 `switch must be exhaustive`，搜索 `case .fourKHDGallery` 找到所有需更新的 switch
- `WorkspaceToolbarHost.swift` 和 `WorkspaceCommandValidator.swift` 中有最多的 switch 语句需更新
- 文件名冲突：两个不同目录的同名 .swift 文件会产生 `Multiple commands produce` 错误，需重命名其中一个
