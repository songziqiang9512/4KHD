# 4KHD 框架进度交接备忘

> 更新时间：2026-04-05（第二次续写）
> 目的：为后续继续开发提供一份短路径交接文档，避免上下文截断后丢失状态

---

## 1. 当前结论

4KHD 第一阶段“框架搭建”已经基本成立，可以进入下一步。

当前已经完成的不是单纯目录占位，而是已经能实际运行的原生骨架：

- 应用可正常启动
- 主窗口可正常显示
- 三栏结构已经接好
- 左侧路由、中间图库列表、右侧详情区可以联动
- 数据流已经不是 UI 直接写死，而是通过 `Services/DataSource -> Models -> ViewModel -> UI`
- 4KHD 站点的列表/详情解析已经有独立解析层
- 脚本桥和 `WKWebView` 桥都已经有明确落点

因此，当前阶段可以视为：

**框架完成，进入真实数据与真实资源加载阶段。**

---

## 2. 当前目录与职责

当前工程核心目录已经形成：

```text
4KHD/
├── App/                     ← 启动入口、主菜单、主窗口协调
├── Shell/                   ← 三栏结构、内容路由
├── Models/                  ← 图库列表、详情、图片项、路由等模型
├── Modules/GalleryLibrary/  ← 图库浏览模块
├── Services/
│   ├── DataSource/          ← 4KHD 数据源、HTML 解析、脚本桥
│   ├── WebViewBridge/       ← WebView 桥接骨架
│   └── Cache/               ← 缩略图缓存骨架
├── Shared/
│   ├── UI/                  ← 空状态、加载态、Inspector 外壳
│   └── Foundation/          ← AppError、LaunchLogger
└── Resources/Fixtures/      ← 当前开发期 HTML 夹具
```

---

## 3. 已完成项

### 3.1 启动与窗口

已完成：

- 使用 `main.swift` 显式接管应用启动
- `AppDelegate` 中完成激活策略、主菜单安装、窗口展示
- 主窗口由 `MainWindowCoordinator` 管理
- 窗口已支持进入当前活跃 Space
- 初始窗口位置改为按当前屏幕可见区域计算，而不是依赖恢复状态

关键文件：

- `4KHD/App/main.swift`
- `4KHD/App/AppDelegate.swift`
- `4KHD/App/AppMenuBuilder.swift`
- `4KHD/App/MainWindowCoordinator.swift`

### 3.2 Shell 与页面骨架

已完成：

- `NavigationSplitView` 三栏结构
- 左侧基础导航：图库 / 收藏 / 最近浏览
- 中间图库列表卡片
- 右侧详情面板

关键文件：

- `4KHD/Shell/RootSplitView.swift`
- `4KHD/Shell/SidebarView.swift`
- `4KHD/Shell/ContentRouter.swift`

### 3.3 数据模型

已完成：

- `GalleryListItem`
- `GalleryDetail`
- `GalleryImageItem`
- `AppRoute`
- `LoadState`
- `SourceSite`
- `FavoriteRecord`

这些模型当前已经真实被 UI 和数据层消费。

### 3.4 数据源与解析

已完成：

- `FourKHDDataSource`
- `FourKHDHTMLParser`
- `GalleryFixtureLoader`
- `GalleryScriptBridge`
- `GalleryListService`
- `GalleryDetailService`

当前数据优先级已经更新为：

1. 列表页优先走原生远程抓取 `https://www.4khd.com/`
2. 详情页优先走列表项携带的真实 `detailURL`
3. 如果存在脚本输出 `Scripts/outputs/<id>/summary.json`，详情页可回退到脚本结果
4. 最后回退到 `Resources/Fixtures` 中的本地 HTML 夹具

这意味着：

- 当前 UI 已经是“解析驱动”
- 解析器不再只认自定义 fixture 标记，也已经兼容真实 4KHD 的 WordPress 页面结构
- 后面接真实页面抓取时，不需要重写页面结构

新增关键文件：

- `4KHD/Services/DataSource/FourKHDRemoteFetcher.swift`

新增说明：

- `FourKHDHTMLParser` 现在已支持两套结构：
  - 开发期 fixture 的 `entry-card / entry-title`
  - 真实 4KHD 列表页的 `wp-block-post-template / wp-block-post-title`
- 详情解析已支持：
  - `h3.wp-block-post-title`
  - `canonical`
  - `page-numbers`
  - 正文图片链接与图片节点提取

### 3.5 脚本桥

已完成：

- 本地脚本 `Scripts/4khd_gallery_dump.py` 已加入当前仓库
- 详情页“重新解析”按钮已经能尝试调用脚本重新生成结构化结果

注意：

- 真实运行时是否能联网、是否能访问代理，当前仍受运行环境影响
- 这不影响框架完整性，但会影响真实图片与真实详情抓取结果

### 3.6 WebView 桥

已完成：

- `WebViewCoordinator` 已建好
- 数据层与详情加载流程已经为 WebView 预留接入口

当前状态：

- 为了避免 GPU / WebProcess 崩溃干扰启动排查，启动期预加载暂时关闭

---

## 4. 当前已知问题

这些问题属于“下一阶段待处理”，不影响判断框架已成立：

### 4.1 图片仍然是占位/加载失败

原因：

- 当前运行环境下网络访问受限
- `images.unsplash.com`、`i0.wp.com` 等资源请求失败
- WebKit GPU/WebProcess 在受限环境下也出现过崩溃日志

结论：

- 这是资源加载问题，不是框架结构问题

### 4.2 UI 还处于骨架阶段

表现：

- 首屏风格偏占位
- 卡片和详情区还没有真正的产品级设计
- 网格密度、分隔比例、视觉层次还需要重新设计

结论：

- 当前以“跑通结构”为主，UI 打磨在下一阶段进行

### 4.3 窗口初始尺寸体验刚修正

虽然主窗口现在已经能显示，但仍建议后续继续优化：

- 最佳初始宽高
- 三栏默认比例
- 窗口首次打开时的动画与观感

---

## 5. 推荐的下一步

下一步不要再回头重构框架，直接进入“真实数据与真实加载”阶段。

建议顺序：

1. 验证真实 4KHD 列表和详情是否能在当前用户环境稳定抓到
2. 接 `WKWebView` 注入 JS，提取真实图片节点
3. 建立统一的图片加载回退链路
4. 给列表/详情增加“当前数据来源”调试信息
5. 再做 UI 打磨和交互细化

---

## 6. 下一阶段最值得优先做的代码点

### 6.1 当前刚完成的接入点

已完成：

- `FourKHDRemoteFetcher` 原生抓取首页 HTML
- 列表项真实 `detailURL` 贯通到详情请求链路
- 详情优先尝试远程页面解析，再回退脚本与 fixture

这一步之后，工程已经进入“真实数据优先”阶段，不再是纯本地样本演示。

### 6.2 下一步应优先验证的点

目标：

- 用户当前机器上，首页是否已经显示真实线上内容
- 选中任一图集后，右侧是否能解析出真实标题、分页和图片节点
- 如果网络受限，是否能平稳回退到脚本或 fixture

### 6.3 WebView 注入链路

目标：

- `WKWebView` 加载真实详情页
- 注入 JS 收集图片节点
- 回传给原生层

建议：

- 当前不要把 WebView 直接做成主界面
- 仍保持“原生 UI 为主，WebView 为辅助资源解析器”

### 6.4 图片加载器

目标：

- 统一管理：
  - 直接 URL 加载
  - 脚本结果 URL 加载
  - WebView 节点回退
  - 本地缓存回退

---

## 7. 启动与调试说明

当前已经加入启动日志：

- 文件：`/tmp/4khd-launch.log`

用途：

- 调试应用是否进入 `main.swift`
- 调试 `AppDelegate`
- 调试建窗与激活流程
- 调试窗口成为 key/main 的时机

若后续启动问题再次出现，先看这个日志。

---

## 8. 一句话结论

当前状态已经不是“准备搭框架”，而是：

**框架已经搭好，下一步应直接进入真实 4KHD 数据抓取、WebView 资源解析和图片加载链路实现。**
