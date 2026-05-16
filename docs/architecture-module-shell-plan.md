# 4KHD 模块化底壳与目录规划

## 1. 目标

这份规划的目标不是单纯整理目录，而是把 4KHD 逐步演进成一个可持续发展的桌面应用底壳：

1. 任意业务模块可插拔。
2. 删除任意一个模块后，不影响其他模块运行。
3. 新增模块时，不需要继续把逻辑堆进现有 `WorkspaceShell`。
4. 公共能力集中沉淀，避免本地模块、4KHDGallery 模块、未来新模块重复造轮子。
5. 保持当前项目体量下的实现克制，不为“模块化”引入过度抽象。

这里的“底壳”不是空架子，而是指：

- App 入口
- 窗口与三栏工作区框架
- 模块路由
- 共享 UI 容器
- 共享平台能力
- 模块注册与接入约束

业务模块则是：

- 4KHDGallery
- LocalLibrary
- Favorites（可视为独立横切模块）
- 未来新增模块

## 2. 当前项目结构扫描结论

当前项目已经具备“多模块应用”的雏形，但边界还没有完全拉开。

### 2.1 已有结构

当前顶层源码目录：

- `App/`
- `Shell/`
- `Shared/`
- `Modules/`

### 2.2 当前问题

#### 2.2.1 顶层目录已收敛，但壳层文件仍偏大

`App / Shell / Shared / Modules` 已经落地，目录维度混杂问题基本解决。

当前更真实的问题是：

1. `WorkspaceShell.swift` 仍同时承载 sidebar、split layout、沉浸态浮层、toolbar 等多项职责。
2. sidebar 和 immersive 相关实现还没有从 `WorkspaceShell.swift` 里进一步拆开。
3. 详情区开合、工具栏按钮、中栏避让策略还没有上升为壳层级布局状态。

#### 2.2.2 模块装配已经上提，但模块接入面仍可继续稳定化

当前已完成：

1. `App` 层负责模块实例创建和 `WorkspaceModuleRegistry` 组装。
2. `Shell` 通过注册表渲染模块 sidebar / content / detail。
3. `WorkspaceAppContext` 不再直接持有具体模块 store。

当前还需要继续关注：

1. 模块 toolbar 仍主要分散在各 content / detail view 内，壳层还没有统一的 toolbar host。
2. 路由表达虽然已经是 `moduleID + itemID`，但中栏与详情区联动状态还没有抽成专门的壳层布局状态。

#### 2.2.3 Shared 层已经建立，但中栏体验尚未统一

目前已经完成的共享沉淀包括：

1. `RemoteImagePipeline / LocalImageCache / DetailPageImageCache`
2. `CookieBridge`
3. `ZoomableImageCanvas`
4. `HorizontalFilmstrip`
5. 若干详情区共享控件与平台桥接

当前仍不统一的部分是中栏体验：

1. 在线中栏网格是 `SwiftUI LazyVGrid`
2. 本地中栏网格是 `AppKit NSCollectionView` 瀑布流
3. 两者在代码形态和布局能力上不同，后续统一时应优先统一壳层行为和交互结果，而不是强行统一到底层实现。

#### 2.2.4 Favorites 已独立出记录模型，但还不是通用收藏平台

当前 `Favorites` 已经只持有自己的 `FavoriteRecord`，不再直接依赖 `GalleryItem`。

但它仍主要服务于 `4KHDGallery`，距离真正的“可服务多个业务模块的收藏平台”还差一层通用资源标识设计。现阶段不应为了未来可能性过早抽象。

## 3. 规划原则

### 3.1 顶层按“壳层 / 共享层 / 模块层”划分

未来源码结构不再按 `Local / Web / UI / Core` 混排，而是统一成：

- `App`
- `Shell`
- `Shared`
- `Modules`

### 3.2 模块内部再按职责分层

每个模块内部使用统一分层：

- `Domain`
- `State`
- `Services`
- `UI`

需要时可加：

- `Platform`
- `Support`

但只在确实有规模时再加，不为了对称性硬建空目录。

### 3.3 共享层只容纳真正跨模块的能力

只有至少两个模块会用到的能力，才进入 `Shared`。

不满足这个条件的逻辑，默认留在模块内。

### 3.4 壳层不依赖模块内部实现细节

底壳只依赖模块暴露出来的“接入面”：

- 模块标识
- 模块标题 / 图标
- 模块 sidebar 节点
- 模块中栏 View
- 模块详情栏 View
- 模块级命令与 toolbar 注入能力

底壳不应直接依赖：

- 4KHDGallery 的 HTML 解析器
- LocalLibrary 的目录扫描细节
- Favorites 的分组规则

### 3.5 先建立边界，再逐步搬迁

本规划优先定义目标结构与职责边界。

实际迁移应分阶段完成，不建议一次性全量重构。

## 4. 目标目录结构

建议的目标目录如下：

```text
4KHD/
  App/
    FourKHDApp.swift
    WorkspaceAppAssembly.swift

  Shell/
    WorkspaceShell.swift
    WorkspaceModuleRegistry.swift
    WorkspaceRoute.swift
    WorkspaceLayout/
    Immersive/
    Toolbar/

  Shared/
    Domain/
    State/
    Services/
    UI/
    Platform/

  Modules/
    4KHDGallery/
      Domain/
      State/
      Services/
      UI/

    LocalLibrary/
      Domain/
      State/
      Services/
      UI/

    Favorites/
      Domain/
      State/
      Services/

  Resources/
```

说明：

- `App` 只做 app 入口与场景组装
- `Shell` 是通用工作区壳，不属于任何具体模块
- `Shared` 是跨模块复用层
- `Modules` 才是真正的业务模块承载区

当前落地状态：

1. `WorkspaceSidebar` 还在 `WorkspaceShell.swift` 内部同文件实现，尚未独立成文件。
2. `ImmersiveController` 也仍与 `WorkspaceShell.swift` 同文件，后续可按收益再拆。
3. `Toolbar/`、`WorkspaceLayout/` 还属于规划目标，尚未单独形成目录。

## 5. 底壳架构设计

## 5.1 底壳职责

底壳必须稳定承担以下职责：

1. 创建主窗口与 Scene。
2. 持有模块注册表。
3. 维护当前工作区选择状态。
4. 负责三栏工作区布局。
5. 提供通用沉浸模式。
6. 提供统一 toolbar 容器。
7. 注入共享服务与共享环境。
8. 让模块按约定挂载自己的 sidebar / content / detail。

底壳不负责：

1. 网站列表抓取。
2. 本地目录扫描。
3. 收藏规则。
4. 模块内业务状态协调。
5. 模块自己的详情解析。

## 5.2 底壳的核心对象

底壳建议围绕以下对象建立：

### 5.2.1 ModuleRegistry

作用：

- 注册当前可用模块
- 提供模块元信息
- 提供模块装配入口

它是“有哪些模块”这一事实的唯一来源。

### 5.2.2 WorkspaceRoute / SidebarSelection

作用：

- 表示当前路由落在哪个模块、哪个节点
- 由壳层持久化

未来不应再把在线 section 与本地 folder 直接硬编码进壳层枚举中。

当前 `SidebarSelection` 应逐步演进为更通用的路由表达：

```text
moduleID + moduleScopedSelectionPayload
```

### 5.2.3 WorkspaceShell

作用：

- 根据当前 route 渲染 sidebar / content / detail
- 决定三栏显示策略
- 提供共享 overlay、沉浸模式、toolbar 容器

### 5.2.4 WorkspaceLayoutState

作用：

- 保存三栏尺寸
- 记忆详情是否展开
- 记忆沉浸前后的布局状态

这是壳层状态，不属于任何模块。

### 5.2.5 WorkspaceToolbarHost

作用：

- 聚合壳层 toolbar
- 聚合当前模块 toolbar
- 避免未来模块都直接改主壳 toolbar

## 5.3 模块接入协议

为了做到“删掉模块也不影响其他模块”，每个模块都必须只通过一个明确的接入面挂进壳层。

建议采用“模块描述对象 + 模块根视图工厂”的方式，而不是复杂协议树。

建议接入面至少包含以下信息：

### 5.3.1 模块元信息

- `moduleID`
- `displayName`
- `sidebarIcon`
- `defaultEntry`

### 5.3.2 模块 sidebar 接入

- 模块如何生成自己的 sidebar 节点
- 模块如何把 sidebar 选择映射回自身状态

### 5.3.3 模块内容区接入

- 当前 selection 下，中栏显示什么

### 5.3.4 模块详情区接入

- 当前 selection 下，详情区显示什么

### 5.3.5 模块 toolbar 接入

- 当前模块可向壳层提供 toolbar 内容

### 5.3.6 模块 commands 接入

- 当前模块如有菜单命令，也应通过模块接入面注册

## 5.4 模块可插拔约束

为了保证模块真正可删可加，每个模块必须满足这些约束：

1. 模块源码只能依赖 `Shared` 和必要系统框架。
2. 模块不能直接依赖另一个模块的内部文件。
3. 壳层不能硬编码某个模块的内部类型。
4. 模块被移除后，`ModuleRegistry` 中不注册即可，壳层仍然能启动。
5. 模块自己的 store、service、resolver 必须留在模块边界内。

## 6. Shared 层规划

## 6.1 Shared/Domain

这里只放跨模块通用的概念模型。

当前不建议一开始就强行统一线上 / 本地模型。

短期内可以先保持为空，或者只放非常明确的公共类型，例如：

- 共享的视图状态枚举
- 与来源无关的展示模型

原则：

- 如果一个类型明显带业务语义，就不要进 Shared/Domain

例如：

- `GalleryItem` 不应进入 Shared/Domain
- `LocalImageItem` 不应进入 Shared/Domain

## 6.2 Shared/State

适合容纳：

- `ImmersiveController`
- `WorkspaceLayoutState`
- 将来跨模块共享的 UI 状态

这些是壳层级状态，不属于任何业务模块。

## 6.3 Shared/Services

这里应该收纳真正的共享能力服务。

当前明确适合进入 Shared/Services 的有：

### 6.3.1 图片加载与缓存

- `RemoteImagePipeline`
- `LocalImageCache`
- `DetailPageImageCache`

### 6.3.2 Cookie / 会话桥接

- `CookieBridge`

### 6.3.3 未来可进入的能力

- 下载服务
- 文件导出服务
- 缩略图缓存服务
- 预取调度服务

原则：

- 服务层做“能力”，不做“模块业务”

例如：

- `DetailPageHTMLResolver` 不应进 Shared，它属于 4KHDGallery 业务服务

## 6.4 Shared/UI

这里放所有可跨模块复用的 UI 组件与交互件。

当前建议进入 Shared/UI 的有：

- `ZoomableImageCanvas`
- `StepButton`
- `DetailStatusBadge`
- `DetailPlaceholder`
- `KeyDownCatcher`
- 共享的 filmstrip tile / 占位组件
- 通用加载态 / 空态组件

当前 `SmallViews.swift` 可拆到这里，但不建议继续保持“大杂烩单文件”形式。

建议按职责拆分成：

- `ImagePlaceholders.swift`
- `DetailControls.swift`
- `KeyboardSupport.swift`
- `StatusBadges.swift`

## 6.5 Shared/Platform

这里放 macOS 平台桥接与宿主适配层。

当前适合进入这一层的有：

- `LocalQuickLookController`
- `LocalDesktopWallpaperSetter`
- 各类 `NSViewRepresentable` 桥接
- Finder 打开 / Reveal 支持
- 将来如果有窗口行为桥接、toolbar bridge，也放这里

原则：

- 这是“平台适配层”，不是“业务功能层”

## 7. 模块规划

## 7.1 4KHDGallery 模块

这是当前在线模块的标准命名，后续统一使用：

- `Modules/4KHDGallery`

### 7.1.1 职责

负责：

- 4KHD 网站分类列表
- 搜索
- 图集分页
- 图集详情解析
- 在线图片详情浏览
- 收藏联动

不负责：

- 壳层工作区布局
- 通用沉浸模式
- 通用图片缓存底层

### 7.1.2 建议目录

```text
Modules/4KHDGallery/
  Domain/
    GallerySection.swift
    GalleryItem.swift
    ImageSlot.swift
    ResolvedImagePage.swift

  State/
    GalleryFeedStore.swift
    GalleryDetailStore.swift
    FourKHDGalleryStore.swift

  Services/
    SiteListResolver.swift
    DetailPageHTMLResolver.swift
    DetailImageResolverView.swift
    GalleryRequestFactory.swift
    GalleryFavoritesBridge.swift

  UI/
    GalleryContentList.swift
    GalleryRow.swift
    GalleryGridCard.swift
    ImageDetailPane.swift
    Filmstrip.swift
```

### 7.1.3 关于当前 FourKHDGalleryStore

当前 `FourKHDGalleryStore` 已经作为 4KHDGallery 模块门面使用，负责聚合 feed / detail / favorites 三块状态给现有 view 使用。

后续如果继续收敛耦合，可考虑逐步让 view 直接注入更窄的子 store，但这不应先于壳层布局稳定化。

## 7.2 LocalLibrary 模块

### 7.2.1 职责

负责：

- 导入本地目录
- 扫描图片树
- 本地图片搜索 / 排序 / 展示
- 本地图片详情查看
- QuickLook / Finder Reveal / 保存副本

不负责：

- 壳层 sidebar 基础结构
- 通用沉浸模式
- 在线抓取逻辑

### 7.2.2 建议目录

```text
Modules/LocalLibrary/
  Domain/
    LocalLibraryRoot.swift
    LocalFolderNode.swift
    LocalImageItem.swift
    LocalImageMetadata.swift

  State/
    LocalLibraryStore.swift

  Services/
    LocalFolderScanner.swift
    LocalImageMetadataService.swift
    LocalFileAvailabilityMonitor.swift

  UI/
    LocalSidebar/
    Content/
      LocalImageContentList.swift
      LocalImageRow.swift
    Detail/
      LocalImageDetailPane.swift
      LocalImageInfoView.swift
      LocalImageInspectorOverlay.swift
    Grid/
      LocalImageWaterfallGrid.swift
      LocalImageGridContainerView.swift
      LocalImageGridCollectionView.swift
      LocalImageGridLayout.swift
      LocalImageGridContextMenu.swift
      LocalImageGridSupport.swift
```

### 7.2.3 对当前文件名的建议

当前 `LocalImageContentList.swift` 实际包含的是中栏内容页，不只是 folder pane。

建议重命名为：

- `LocalImageContentList.swift`

扫描、排序、搜索相关逻辑则逐步拆出到 `Services`。

## 7.3 Favorites 模块

Favorites 建议作为独立横切模块存在，不再只是 4KHDGallery 的附属文件。

### 7.3.1 职责

负责：

- 收藏存储
- 收藏反查
- 收藏列表持久化
- 收藏记录模型

### 7.3.2 建议目录

```text
Modules/Favorites/
  Domain/
    FavoriteRecord.swift

  State/
    FavoritesStore.swift

  Services/
    FavoriteAuthorGrouping.swift
```

说明：

1. 当前 `FavoritesStore` 已只管理 `FavoriteRecord`，不再直接持有 `GalleryItem`。
2. 作者分组策略目前仍以 `GalleryItem` 为输入，更准确的归属应在 `4KHDGallery`，后续可按收益再迁移。
3. 未来如果别的模块也支持收藏，应由各模块自行提供记录模型到业务模型的桥接，而不是反向让 `Favorites` 依赖业务模块。

## 8. Shell 详细规划

## 8.1 建议目录

```text
Shell/
  WorkspaceShell.swift
  WorkspaceSidebar.swift
  SidebarSelection.swift
  ModuleRegistry.swift

  Immersive/
    ImmersiveController.swift
    ImmersiveToolbarVisibilityController.swift
    ImmersiveMouseTracker.swift

  WorkspaceLayout/
    WorkspaceLayoutState.swift
    WorkspaceSplitLayoutStore.swift

  Toolbar/
    WorkspaceToolbarHost.swift
```

## 8.2 Sidebar 结构

未来 sidebar 不应再由壳层硬编码：

- 线上 section 列表
- 本地目录树

而应改成：

1. 壳层绘制 sidebar 容器
2. 各模块提供自己的 sidebar 节点
3. 壳层负责统一 selection 与样式

这样新增模块时，不需要继续改壳层 switch。

## 8.3 Content / Detail 渲染方式

未来壳层应通过当前 route 找到模块，然后由模块提供：

- content view
- detail view

壳层不应该继续写：

- `case .online`
- `case .local`

这种 switch 未来会随模块数增长不断膨胀。

## 8.4 Toolbar 规划

当前 toolbar 很容易继续膨胀成“所有模块都往主壳塞按钮”。

建议分层：

1. 壳层 toolbar
   - 全局窗口行为
   - 导入入口
   - 全局设置

2. 模块 toolbar
   - 由当前激活模块提供

3. 详情级 toolbar
   - 由当前模块 detail 自己注入

由 `WorkspaceToolbarHost` 统一拼装，避免 toolbar 代码散落。

当前现状补充：

1. 搜索框仍由各内容视图通过 `.searchable(..., placement: .toolbar)` 注入。
2. 主壳 toolbar 当前主要承载缓存容量和导入目录。
3. “详情区展开/折叠”这类布局控制应优先放入壳层 toolbar，而不是继续分散在模块内部 toolbar。

## 9. 状态层规划

## 9.1 全局状态与模块状态分离

未来状态应分成两类：

### 9.1.1 全局 / 壳层状态

- 当前 route
- 工作区布局
- 沉浸模式
- 全局偏好项

### 9.1.2 模块状态

- 4KHDGallery 的列表 / 搜索 / 详情状态
- LocalLibrary 的目录树 / 排序 / 选图状态
- Favorites 的收藏状态

原则：

- 壳层状态不依赖模块业务字段
- 模块状态不反向操控壳层内部实现

## 9.2 Store 命名建议

建议统一：

- 模块聚合 store 使用 `XXXStore`
- 明确模块名前缀

例如：

- `FourKHDGalleryStore`
- `LocalLibraryStore`
- `FavoritesStore`
- `WorkspaceLayoutState`

避免再出现过于宽泛的名字，如：

- `FourKHDGalleryStore`

## 10. 服务层规划

## 10.1 Shared Services 与 Module Services 的边界

### Shared Services

只处理跨模块能力，例如：

- 图片下载
- 图片缓存
- cookie 同步
- 平台桥接

### Module Services

只处理模块业务，例如：

- 4KHDGallery 的 HTML 解析
- LocalLibrary 的目录扫描
- Favorites 的作者分组策略

## 10.2 当前文件的建议归属

### 应进入 Shared/Services

- `RemoteImagePipeline`
- `LocalImageCache`
- `DetailPageImageCache`
- `CookieBridge`

### 应进入 4KHDGallery/Services

- `SiteListResolver`
- `DetailPageHTMLResolver`
- `DetailImageResolverView`
- `ApifyLibrary`（如果继续保留为 4KHD 数据源初始化支持）

### 应进入 LocalLibrary/Services

- 目录扫描逻辑
- metadata 读取逻辑
- 文件可用性监控逻辑

## 11. 文件拆分建议

## 11.1 不建议继续保留的大文件 / 混合文件

### WorkspaceShell.swift

当前承担过多职责，建议拆成：

- `WorkspaceShell.swift`
- `WorkspaceSidebar.swift`
- `SidebarSelection.swift`
- `ImmersiveController.swift`
- `ImmersiveChrome.swift`

### SmallViews.swift

当前是实用组件杂烩，建议至少按职责拆开。

### LocalImageContentList.swift

建议改名并拆出服务逻辑。

当前补充：

1. `LocalImageContentList` 的导入面板与 metadata 读取已拆到模块 `Services`。
2. 真正还偏重的部分，是本地 `AppKit` 网格与内容视图的联动状态。

## 11.2 适合保留同文件的情况

对于强耦合的小型 View 附件，可以保留同文件：

- 某个主视图的局部 badge
- 只被该页面使用的小 section header

原则：

- 单文件聚合可以接受
- 但不能让“壳层 + 路由 + 侧栏 + 沉浸模式 + toolbar”全塞在一个文件里

## 12. 模块可删除性设计

为了实现“删掉任何一个模块都不影响其他模块运行”，需要落实这些设计约束：

## 12.1 模块从注册表接入

底壳只认注册表中的模块。

删除模块时：

1. 删除模块目录
2. 删除模块注册
3. 壳层不需要改其他逻辑

## 12.2 模块不得互相直接 import 内部文件

例如：

- LocalLibrary 不应直接依赖 4KHDGallery 的 `GalleryItem`
- 4KHDGallery 不应直接调用 LocalLibrary 的扫描实现

如果确实要协作，只能通过：

- Shared 能力
- Favorites 这类独立共享模块
- 模块公开接入面

## 12.3 空模块 / 缺模块可容错

壳层应支持：

- 没有本地模块时，只显示 4KHDGallery
- 没有 4KHDGallery 时，只显示 LocalLibrary
- 没有任何业务模块时，显示一个基础空工作区

这点非常重要，它决定底壳是否真正独立。

## 13. 新模块接入模板

未来新增模块时，建议统一按以下模板：

```text
Modules/NewModule/
  Domain/
  State/
  Services/
  UI/
```

新增模块必须提供：

1. 模块 ID
2. 模块显示名称
3. sidebar 节点定义
4. content view
5. detail view
6. 可选 toolbar 注入
7. 可选 commands 注入

新增模块不应要求：

1. 修改 `WorkspaceShell` 内部布局逻辑
2. 修改其他模块的 store
3. 修改共享层已有边界

如果新增模块必须大改壳层，说明边界设计仍不够稳定。

## 14. 建议的渐进迁移路线

## 阶段 1：先建立目录边界，不改行为

目标：

- 建立 `Shell / Shared / Modules`
- 把现有文件按职责迁移到新目录
- 不改变功能行为

验收：

- 工程可编译
- 路由、搜索、详情、本地目录功能保持一致

当前状态：已完成。

## 阶段 2：收拢 4KHDGallery 模块

目标：

- 把当前散落的在线代码集中到 `Modules/4KHDGallery`

验收：

- 线上列表、搜索、详情不回归
- Shell 不再直接依赖在线模块内部文件名

当前状态：已完成。

## 阶段 3：收拢 LocalLibrary 模块

目标：

- 把 `Local` 目录迁移成 `Modules/LocalLibrary`
- 拆出扫描与 metadata 服务

验收：

- 本地目录导入、扫描、搜索、排序、详情保持一致

当前状态：已基本完成。
未完成细项：

1. 本地中栏和 `AppKit` 网格布局的壳层联动状态还未统一。

## 阶段 4：建立 Shared 层

目标：

- 把跨模块图片加载 / 缓存 / 平台桥接沉淀到 Shared

验收：

- 本地和 4KHDGallery 都只依赖 Shared 能力
- 不再互相复制相似底层逻辑

当前状态：已部分完成。
已落地：

1. 图片缓存与请求基础设施
2. cookie 桥接
3. 详情区共享控件与共享 filmstrip

仍待推进：

1. 中栏共享交互骨架
2. 详情区展开/折叠后的统一布局行为

## 阶段 5：壳层模块注册化

目标：

- 引入 `ModuleRegistry`
- 用模块接入面替代 `WorkspaceShell` 内部的硬编码 switch

验收：

- 删掉任一模块后，壳层仍可启动
- 新增一个空白测试模块时，只需注册，不需重写壳层

当前状态：已大体完成，但还未完全收尾。
已落地：

1. `WorkspaceModuleRegistry`
2. `WorkspaceRoute`
3. `WorkspaceAppAssembly`
4. `WorkspaceAppContext` 壳层化

仍待推进：

1. `WorkspaceShell` 内部大文件拆分
2. 壳层级 detail 开合状态、toolbar host、内容区联动布局

## 15. 最终推荐状态

当这份规划执行到位后，4KHD 的理想状态应是：

1. `App` 很薄，只负责入口。
2. `Shell` 很稳，只负责工作区底壳。
3. `Shared` 很克制，只放跨模块能力。
4. `Modules/4KHDGallery`、`Modules/LocalLibrary`、`Modules/Favorites` 边界清晰。
5. 删掉任一模块，不会破坏其他模块编译和运行。
6. 新增模块时，只需要实现模块自身并接入注册表。

这才是后续可持续发展的结构。

## 16. 本规划下的命名建议摘要

建议保留：

- `WorkspaceShell`
- `LocalLibraryStore`
- `FavoritesStore`
- `ImmersiveController`

建议新增：

- `ModuleRegistry`
- `WorkspaceLayoutState`
- `WorkspaceToolbarHost`

## 17. 结论

4KHD 现在已经不是一个单模块小工具，而是一个明确会继续增长的多模块工作区应用。

因此最重要的不是继续在现有目录上修修补补，而是尽快确立三件事：

1. 底壳独立。
2. 模块边界独立。
3. 公共能力独立。

这份规划的核心不是“目录漂亮”，而是确保以后：

- 加模块不痛苦
- 删模块不连坐
- 调整 UI 壳层不牵扯业务抓取
- 调整业务实现不伤到底壳

后续如果开始正式迁移，建议严格按“先搬目录和命名，再改接入方式，最后做注册化”的顺序推进，避免一步做太多导致结构和行为同时失稳。
