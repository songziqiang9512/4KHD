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

## 7. 最近完成的工作（2026-05-27）

### 第一轮：功能补全（P0 + P1 + P2）

**收藏接入（P0）：** MissKonFavoritesBridge + 共享 FavoritesStore + 工具栏 heart 按钮
**MissKon Inspector（P1）：** 标签/图片数/页数/Section/收藏状态/URL
**详情区重试（P1）：** showFailure(retry:) + retry 按钮 + force resolve
**搜索高亮（P1）：** 列表/网格黄色匹配高亮，复用 highlightedAttributedString
**缓存持久化（P2）：** Codable MissKonItem，Application Support JSON 文件
**keyDown 转发（P2）：** Shared/UI/Detail/WorkspaceDetailRootView

### 第二轮：性能优化 + Bug 修复

**Bug 修复：** saveMessage 未观察、isApplyingSelection 守卫缺失
**性能：** 列表增量更新（ID 不变跳过 reloadData）、网格 refreshVisibleItems、缓存 1h 过期
**共享：** NSView.performWithoutAnimation → Shared/Platform/
**UI：** SF Symbols 图标对齐（safari/doc.on.doc/square.and.arrow.up）

### 第三轮：架构对齐

**回调模式：** `feed.onSelectionChanged` 闭包（对齐 GalleryFeedStore）
**Task 清理：** `loadTask`/`searchTask` 完成后 nil
**收藏追踪：** 详情区 observeState 添加 `favorites.favorites` 观察

### 第四轮：缺陷修复

**selectedItemID setter：** 修复 setter 不触发 detail 更新，添加 `feed.selectedItem`
**初始选择：** init 调用 `restoreSectionCache` 确保缓存即时展示
**拖放：** 表格 `pasteboardWriterForRow` + `forLocal:true`
**页脚行高：** `tableView(_:heightOfRow:)` 页脚 34pt
**detailFailed：** 添加状态标志 + "解析失败"/"解析中" 连贯文字
**@Observable：** MissKonDetailInteractionController 添加宏，保存状态实时更新
**force-unwrap：** 3 处 `Range(...)!` 替换为 guard-let
**搜索自动选择：** `submitSearch` 后 auto-select + onSelectionChanged

### 第五轮：数据完整性审计（关键 Bug）

**String.Index 跨实例：** `html.lowercased()` 索引用于 `html` 子脚本，未定义行为可致 crash。重写为 NSString/NSRange API。
**resolvePageURLs 子页 URL：** 子页 URL 被当作首页构造，多页图集第 2+ 页 URL 错误。从 baseURL 剥离页面号。
**收藏跨模块泄漏：** 共享 FavoritesStore 导致 Gallery/MissKon 记录互现。两桥添加 `detailURL.host` 域名验证。
**aspectRatio 安全：** `aspectRatioProvider` 添加 `isFinite` / `>0` 检查。
**selectAdjacent 回退：** 添加 `collectionView.selectionIndexPaths.first?.item` 回退。

### 第六轮：用户反馈 Bug 修复

**侧边栏选中态：** `routeMatches` 添加 `.missKon` case
**列数按钮：** GalleryContentPreferences 添加 `gridColumnCount` + 工具栏按钮 + snapshot 字段
**刷新按钮：** `.favorites` section 调用 `restoreSectionCache`
**图片张数：** `imageCountRegex` 扩展匹配 photos/pics/images/张/p
**胶片条闪烁：** `resolve` 创建初始占位 slot（coverURL），消除空状态过渡
**首次启动无内容：** `refreshFromNetwork` 自动选择第一项
**详情面板重建：** 同模块内复用 detailController，跟踪 `lastDetailModuleID`

### 第七轮：P3 体验补齐

**列表/网格滚动位置：** Gallery/MissKon 在双视图切换时用第一个可见图集 ID 恢复位置，避免切换后跳回选中项或顶部；Gallery 收藏分组列表也按图集 ID 对齐。
**测试现状：** 当前 Xcode 工程只有 `4KHD` App target，尚未配置 XCTest target；单元测试仍是后续 P3。

### 模块状态评估

**4KHDGallery：** 稳定完整。新增 `gridColumnCount` 支持（列数 2-6 可调），列表/网格切换保留滚动位置。
**MissKon：** 完成度约 98%。核心链路完整，数据安全审计通过，收藏跨模块验证，列表/网格切换保留滚动位置。
**LocalLibrary / Favorites：** 稳定无变更。

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
