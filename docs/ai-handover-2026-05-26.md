# 4KHD 项目 AI 交接文档

> 日期: 2026-05-26 | 总 Swift 文件: ~110 | 0 SwiftUI | 纯 AppKit

## 1. 项目是什么

macOS 原生图片浏览应用。三个业务模块：在线图库 (4KHDGallery)、本地图片 (LocalLibrary)、收藏 (Favorites)，以及本次新增的 MissKon 模块。底壳提供三栏工作区（侧边栏 + 中栏列表/网格 + 右侧详情大图），模块通过 WorkspaceModuleRegistry 插拔。

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
                 Detail/ — DetailOverlayChromeView
  Modules/
    4KHDGallery/ — 4KHD.com 在线图库（Domain/State/Services/UI）
    LocalLibrary/ — 本地图片（Domain/State/Services/UI）
    Favorites/   — 收藏记录（Domain/State）
    MissKon/     — misskon.com 在线图库（本次新增，16 文件）
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

要新增一个在线图库模块，参考 `Modules/MissKon/` 的结构：

1. `Domain/` — Section 枚举、Item 结构体、ImageSlot、ResolvedImagePage
2. `Services/` — RequestFactory（HTTP 请求头）、ListResolver（列表页 HTML 解析）、DetailResolver（详情页图片提取）
3. `State/` — FeedStore（列表状态+网络请求）、DetailStore（详情解析状态）、GalleryStore（门面聚合）、ContentPreferences、DetailInteractionController
4. `UI/` — ContentViewController、GridContainerView、ContentViews（列表单元格）、FilmstripView、ImageDetailViewController、RemoteImageView、ZoomableImageView

然后修改 Shell 集成点（共约 10 个文件，搜索 `case .missKon` 或 `case .fourKHDGallery` 找到所有需要添加新 case 的 switch 语句）：
- `WorkspaceRoute.swift` — 添加 moduleID case
- `WorkspaceSidebarNode.swift` — 添加 sidebar 节点 case
- `WorkspaceSidebarDataSource.swift` — 添加 sidebar 分组
- `WorkspaceAppContext.swift` — 添加 store 属性
- `WorkspaceAppAssembly.swift` — 创建并注册模块
- `WorkspaceToolbarContext.swift` — 添加工具栏快照和操作 case
- `WorkspaceToolbarHost.swift` — 添加工具栏 UI 更新 case（约 8 个 switch）
- `WorkspaceCommandValidator.swift` — 添加命令验证 case（约 7 个 switch）
- `WorkspaceShell.swift` — 添加布局切换 case
- `WorkspaceSidebarViewController.swift` — 添加侧边栏选择和图标 case
- `WorkspaceWindowController.swift` — 添加窗口标题 case
- `WorkspaceInspectorWindowController.swift` — 添加 Inspector 刷新 case

## 6. 本轮已完成的工作

### 共享基类提取
- `Shared/UI/WorkspaceTableView.swift` — NSTableView 基类，统一 menu、keyDown、live resize
- `Shared/UI/WorkspaceCollectionView.swift` — NSCollectionView 基类，统一 tracking area、hover、滚动时 hover 更新
- 4 个子类（GalleryContentTableView、LocalImageListTableView、GalleryGridCollectionView、LocalImageGridCollectionView）改为继承共享基类

### 详情区自适应布局
- `LocalImageContentViewController` 观察 `detailPane.isPresented`，详情区开合时触发重载

### 本地搜索增强
- 搜索匹配文件夹名（不仅是文件名）
- 列表和网格视图中匹配文字黄色高亮

### Bug 修复
- 网格视图滚动时 hover 状态 stuck（`WorkspaceCollectionView` 监听 bounds 变化更新 hover）
- MissKon 列表页 titleRegex 捕获组不含 href 属性导致 detailURL 为空
- MissKon 详情页双 page-link 结构导致图片提取失败（已修复 + 添加文档）

## 7. 已知问题

### MissKon 模块
- 详情页 page-link 只显示首尾几页（如 1-4），pageCount 估算为 ceil(imageCount/12)，实际总页数需运行时探测。当前通过遍历估算的 pageURLs 解决，404 的页面会被跳过
- 未实现收藏功能（MissKonSection.favorites 的 siteURL 为 nil）
- 图片保存功能未接入（saveCurrentImage 在 toolbar context 中为 break）
- 搜索仅支持服务端搜索，无本地过滤
- 封面图 aspect ratio 依赖 HTML 中的 width/height 属性，可能不准确

### 整体
- Sparkle 自动更新需要通过 Xcode GUI 添加 SPM（`File → Add Package Dependencies → https://github.com/sparkle-project/Sparkle`），CLI 无法完成二进制框架的添加
- 项目无单元测试

## 8. 建议的下一步

### 高优先级
1. **端到端测试 MissKon 模块** — 启动应用，点击 MissKon 侧边栏，验证列表加载、详情页图片浏览、翻页、搜索
2. **修复 MissKon 图片保存** — 在 `MissKonDetailInteractionController` 和 toolbar context 中补全保存逻辑

### 中优先级
3. **完善 MissKon 收藏** — 复用 Favorites 模块，添加收藏存储和侧边栏显示
4. **MissKon section 扩展** — 添加更多 tag 页面作为 section（当前只有 latest 和 cosplay）

### 低优先级
5. 图片预加载 — 详情浏览时预加载相邻图片
6. 保存进度反馈 — 保存大图时显示进度
7. 侧边栏拖拽导入本地文件夹
8. 在线搜索防抖（当前每次按键触发网络请求）

## 9. 常见编译问题

- 新增模块文件会自动被 Xcode 发现（项目使用文件自动发现），无需手动添加到 pbxproj
- 如果 `xcodebuild` 报 SPM 相关错误，清理派生数据: `rm -rf ~/Library/Developer/Xcode/DerivedData/4KHD-*`
- 如果新增 switch case 后编译报 `switch must be exhaustive`，搜索整个项目中的 `case .fourKHDGallery` 或 `case .localLibrary` 找到所有需要更新的 switch 语句
- `WorkspaceToolbarHost.swift` 和 `WorkspaceCommandValidator.swift` 中有最多的 switch 语句需要更新
