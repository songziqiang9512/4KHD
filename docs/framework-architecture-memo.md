# 4KHD 框架搭建备忘

> 最后更新：2026-04-05
> 当前工程状态：Xcode 默认 AppKit 模板（`AppDelegate + Storyboard + ViewController`）
> 参考来源：
> - `docs/4khd-webview-integration-plan.md`
> - `MyWallpaperX` 现有工程分层与模块组织

本备忘用于给 4KHD 第一阶段搭建提供统一参考，目标是先把工程骨架搭对，再逐步把数据抓取、原生浏览、WebView 辅助加载接进去。

---

## 1. 产品定位

4KHD 要做的是一款面向 macOS 26 的原生图片浏览软件，不直接复刻站点页面，而是采用：

- 原生窗口与信息架构
- 原生列表 / 网格 / 详情浏览体验
- 脚本或解析层负责结构化数据
- `WKWebView` 只负责处理最难稳定的图片加载链路

第一阶段应优先保证：

1. 能稳定浏览图集
2. 能稳定展示结构化信息
3. 能为后续缓存、收藏、下载、标签留出扩展位

---

## 2. 当前判断

结合现有验证结果，4KHD 不适合一开始就走“纯 HTTP 直连原图”的产品路线，更适合采用“三层协作”：

1. 数据采集层：解析列表页、详情页、分页与图片索引
2. 原生视图层：负责侧边栏、筛选、网格、详情、交互
3. WebView 辅助层：负责浏览器环境下的真实图片加载与兜底

这意味着我们要避免两种极端：

- 不要把整站网页直接塞进主界面当成最终产品
- 不要在第一阶段把全部稳定性押在裸图直连下载上

---

## 3. 建议目录结构

建议尽快从当前模板迁移到下面这套结构：

```text
4KHD/
├── 4KHD/
│   ├── App/                     ← App 生命周期、主窗口、菜单、路由协调
│   ├── Shell/                   ← SplitView、侧边栏、内容路由、窗口级框架
│   ├── Models/                  ← 零依赖数据模型
│   ├── Modules/
│   │   ├── GalleryLibrary/      ← 图库浏览主模块
│   │   ├── Favorites/           ← 收藏与本地编目
│   │   └── Settings/            ← 偏好设置与数据源设置
│   ├── Services/
│   │   ├── DataSource/          ← 列表/详情抓取、脚本桥接、解析服务
│   │   ├── WebViewBridge/       ← WKWebView 资源解析、页面注入、消息桥接
│   │   ├── Cache/               ← 缩略图缓存、详情缓存、磁盘索引
│   │   └── Persistence/         ← 收藏、历史、配置落盘
│   ├── Shared/
│   │   ├── UI/                  ← 通用网格、动画、占位、Inspector 宿主
│   │   └── Foundation/          ← 公共协议、通知、错误定义、工具类型
│   ├── Resources/               ← 本地 HTML/JS 注入资源、默认配置
│   └── Assets.xcassets/
├── Scripts/                     ← 解析脚本与调试脚本
├── docs/
└── 4KHD.xcodeproj
```

核心原则：

- `Models` 不依赖 UI、网络或 WebKit
- `Shared` 只放跨模块复用能力，不写业务特化逻辑
- `Modules` 只消费服务，不直接互相引用内部实现
- `WebViewBridge` 是基础设施，不直接变成某个页面的业务控制器

---

## 4. 模块边界建议

### 4.1 App

职责：

- 启动流程
- 主窗口创建
- 菜单命令分发
- 全局级状态接线

建议：

- 尽快从 `Storyboard` 主入口迁移到代码建窗
- 保持 `App` 层不直接持有站点解析细节

### 4.2 Shell

职责：

- 侧边栏
- 顶层内容切换
- 主内容区与详情区布局
- 工具栏与模块切换联动

建议：

- 参考 `MyWallpaperX` 的 `Shell` 思路，由 Shell 负责“页面装配”，而不是让每个模块自己建窗口
- 第一阶段优先落地双栏或三栏结构：侧边栏 + 内容区 + 可选详情浮层

### 4.3 Models

第一批建议定义：

- `GalleryListItem`
- `GalleryDetail`
- `GalleryImageItem`
- `SourceSite`
- `LoadState`
- `AppRoute`
- `FavoriteRecord`

要求：

- 字段命名统一
- 不混入 `NSImage`、`WKWebView`、`NSView`
- 允许直接被脚本输出 JSON 映射

### 4.4 Services/DataSource

职责：

- 列表抓取
- 详情抓取
- 分页解析
- 脚本输出转模型
- 错误归类与重试策略

建议拆分：

- `GalleryListService`
- `GalleryDetailService`
- `GalleryParser`
- `ScriptRunner` 或 `ScriptBridge`

这里是未来适配多个站点的关键层，必须避免把 4KHD 站点规则散落到 UI 里。

### 4.5 Services/WebViewBridge

职责：

- 管理隐藏或半隐藏的 `WKWebView`
- 载入详情页
- 注入 JS 获取真实图片节点
- 获取浏览器上下文中的可用资源 URL
- 向原生层回传解析结果

建议：

- WebView 仅作为资源解析器与兜底加载器
- 不让主浏览体验退化成“网页壳”
- 生命周期由统一的 `WebViewPool` 或 `WebViewCoordinator` 管理

### 4.6 Shared/UI

建议第一批公共组件：

- `GridLayoutHelper`
- `ThumbnailPipeline`
- `AsyncImageCard`
- `InspectorHost`
- `EmptyStateView`
- `LoadingStateView`
- `AppToastPresenter`
- `SelectionController`

共享 UI 的目标是统一行为，不是堆积样式杂项。

---

## 5. 第一阶段推荐页面

第一阶段不宜铺太大，建议先做 4 个页面形态：

1. 图库首页
2. 分类 / 搜索结果页
3. 图集详情页
4. 收藏页

对应关系建议：

- 首页和搜索结果页共用同一套网格浏览容器
- 图集详情页负责展示标题、统计信息、分页、图片序列
- 收藏页先做本地静态编目，不依赖远端实时刷新

---

## 6. 建议数据流

建议统一采用下面这条数据流：

```text
站点 / 脚本 / 解析器
        ↓
DataSource Service
        ↓
Models
        ↓
Module ViewModel / Controller
        ↓
Native View
        ↓
需要时调用 WebViewBridge 做图片解析或兜底展示
```

关键约束：

- 视图不直接拼接站点 URL 规则
- WebView 返回的数据必须先过模型层再进入 UI
- 同一个图集详情不要由多个页面各自重复抓取

---

## 7. 首期页面与交互骨架

建议先固定成下面这套结构：

### 7.1 主窗口

- 左侧：站点入口、分类、收藏、最近浏览
- 中间：图集网格
- 右侧：可开合详情浮层或信息面板

### 7.2 网格卡片

展示：

- 封面
- 标题
- 图片数量
- 分页数量
- 发布时间
- 收藏状态

行为：

- 单击选中
- 双击或回车进入详情
- 右键弹出收藏 / 打开原页 / 复制链接

### 7.3 图集详情

展示：

- 标题与基础元信息
- 图片序列
- 当前加载状态
- 原始详情页入口

行为：

- 分页切换
- 图片缩放
- 逐张查看
- 收藏
- 调用 WebView 重新解析当前图集

---

## 8. 技术取舍建议

### 8.1 UI 技术

建议采用：

- SwiftUI 负责页面组合与状态表达
- AppKit 补足高级网格、窗口、菜单、焦点与性能细节

理由：

- macOS 26 下 SwiftUI 适合做主结构
- 复杂图片网格、键盘交互、右键菜单、焦点控制仍建议保留 AppKit 桥接能力

### 8.2 详情展示

建议优先做原生详情页，不直接以内嵌网页作为详情主体。

允许的例外：

- 图片确实只能在浏览器环境下稳定拿到时，使用隐藏 `WKWebView` 作为后台解析器

### 8.3 脚本接入

建议脚本只承担：

- HTML 获取
- DOM 解析
- JSON 输出

不要让脚本承担：

- UI 状态机
- 收藏管理
- 主线程交互逻辑

---

## 9. 从当前模板迁移的建议顺序

当前仓库还是默认模板，建议按下面顺序清理：

1. 新建 `App/ Shell/ Models/ Modules/ Services/ Shared/ Resources/ Scripts` 目录
2. 把默认 `ViewController.swift` 的职责迁出，不再作为长期主页面
3. 逐步从 `Main.storyboard` 迁移到代码建窗
4. 建立主窗口协调器与根 SplitView
5. 先用假数据跑通网格浏览
6. 再接入 `DataSource Service`
7. 最后接入 `WKWebView` 辅助解析与真实图片链路

这个顺序的好处是：

- 先把 UI 架子立住
- 再接远端不稳定能力
- 出问题时更容易定位是 UI、解析还是 WebView

---

## 10. 第一阶段最小可交付

达到下面标准，就算第一阶段骨架成立：

- 主窗口已经脱离模板式单页控制器
- 侧边栏 + 网格 + 详情骨架可运行
- 有统一的数据模型
- 有独立的数据抓取服务层
- 图集详情可通过原生界面展示
- 必要时可由 `WKWebView` 辅助获得图片显示结果
- 收藏与浏览历史有预留但不必一次做满

---

## 11. 当前不建议过早做的事

- 先做下载器再做浏览器
- 一开始就做多站点通吃
- 让每个页面自己管理一个 `WKWebView`
- 把站点字段直接硬编码进卡片视图
- 过早追求完整离线图库同步

---

## 12. 推荐的首轮文件骨架

建议先落下面这些文件，哪怕内部先是空实现也可以：

```text
4KHD/App/HDApp.swift
4KHD/App/AppDelegate.swift
4KHD/App/MainWindowCoordinator.swift
4KHD/Shell/RootSplitView.swift
4KHD/Shell/SidebarView.swift
4KHD/Shell/ContentRouter.swift
4KHD/Models/GalleryListItem.swift
4KHD/Models/GalleryDetail.swift
4KHD/Models/AppRoute.swift
4KHD/Services/DataSource/GalleryListService.swift
4KHD/Services/DataSource/GalleryDetailService.swift
4KHD/Services/DataSource/GalleryParser.swift
4KHD/Services/WebViewBridge/WebViewCoordinator.swift
4KHD/Services/Cache/ThumbnailCache.swift
4KHD/Modules/GalleryLibrary/UI/GalleryBrowserView.swift
4KHD/Modules/GalleryLibrary/UI/GalleryDetailView.swift
4KHD/Modules/GalleryLibrary/ViewModel/GalleryBrowserViewModel.swift
4KHD/Shared/UI/InspectorHost.swift
4KHD/Shared/UI/LoadingStateView.swift
4KHD/Shared/Foundation/AppError.swift
Scripts/
docs/
```

---

## 13. 一句话结论

4KHD 第一阶段最合适的方向，不是“网页套壳”，也不是“裸 HTTP 下载器”，而是：

**以原生浏览体验为主，数据采集层和 WebView 辅助层为底座的模块化 macOS 26 图片浏览架构。**

后续如无特别原因，本备忘可作为第一轮目录搭建与工程重构的默认依据。
