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

### MissKon 模块重大完善（本轮会话）

**功能补全：**
- 保存图片（Nuke loadData + NSSavePanel + 进度消息）
- 重置缩放（resetToken 观察链，detailInteraction → imageView）
- 网格列数调整（工具栏 +/- 按钮，2~6 列，UserDefaults 持久化）
- 详情区上/下一张导航按钮浮层（DetailNavigationButton）
- 键盘导航（方向键切图、Escape 关闭详情/清除搜索、Enter 打开详情）

**加载优化：**
- 详情渐进加载：首页立即解析并展示，后台继续解析剩余页
- 封面→大图过渡：选中图集先展示封面图，大图加载完成后平滑切换
- 相邻图片预加载（前后各 2 张，RemoteImagePipeline.prefetchDetailImages）
- 按 section 内存缓存：切换侧边栏分类保留已加载数据，避免空白闪烁

**翻页修复：**
- 标准归档页：从 HTML 提取分页链接
- top30 等特殊模板：HTML 无分页元素但有 ≥12 篇文章时自动构造 /page/N/ URL
- 搜索结果去重 + 分页
- 搜索分页路由修复（loadMoreListIfNeeded → loadMoreSearchIfNeeded）

**UI 对齐 4KHDGallery：**
- 胶片条重写：NSVisualEffectView(.hudWindow)、DetailOverlayChromeView、72×96 item、diff-based 更新
- 详情区：.clear 背景、safeArea 顶部约束、chrome 尺寸对齐 Gallery
- 胶片条开关动画（0.2s ease-in-out）、工具栏 toggle 按钮
- 布局偏好传递到工具栏 snapshot（不再硬编码 .grid）

**稳定性：**
- 错误状态红色显示 + "点击重试"，表格/网格 footer 均可点击重试
- 无内容/加载中/已到末尾等清晰状态提示
- section 切换时清除搜索状态，避免竞态
- main actor 隔离警告修复

**代码共享：**
- 提取 `Shared/UI/SharedRemoteImageView.swift`：GalleryRemoteImageView 和 MissKonRemoteImageView 从 86/130 行缩减到 10 行
- MissKon 和 Gallery 共用同一 RemoteImageView 基类，仅 `configureRequest` 闭包不同

**侧边栏分类（8 节点）：**
| 节点 | URL | 说明 |
|------|-----|------|
| 最新 | 首页 | 最新发布 |
| 热门 | /top30/ | 站内热门（支持翻页） |
| Cosplay | /tag/cosplay/ | Cosplay |
| AI 生成 | /tag/ai-enhanced/ | AI 增强/生成 |
| 私房摄影 | /tag/private-photoshoot/ | 私房摄影 |
| 秀人 | /tag/xiuren/ | 国产写真机构 |
| 花漾 | /tag/huayang/ | 人气写真杂志 |
| 收藏 | — | 预留（siteURL = nil） |

### 模块状态评估

MissKon 模块整体完成度约 85%：
- 核心浏览链路完整（侧边栏→列表/网格→分页加载→详情大图→图片切换）
- 边界处理完善（错误重试、空状态、加载态、缓存）
- 用户体验对齐 4KHDGallery（导航按钮、胶片条、键盘、工具栏）
- 已知缺失：收藏集成（独立模块待接入）、Inspector 信息展示、搜索高亮、单元测试
