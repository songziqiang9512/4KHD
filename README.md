# 4KHD

4KHD 是一款 macOS 原生图片浏览软件，用来更稳定、更清晰地浏览 4KHD 网站上的图集内容，并管理本地图片目录。应用界面已迁移为纯 AppKit 实现：主窗口、三栏工作区、侧边栏、工具栏、中栏列表/网格、右侧详情区和缩略图条都由 AppKit 原生控件承载。

这个项目的目标不是把网站页面直接套进一个可见的 WebView，而是把网页解析层隐藏起来，只把最终的图片浏览体验交给原生界面处理。

## 功能特性

- macOS 原生三栏图片浏览界面，整体接近 Mail / Finder 的工作区布局
- AppKit 原生 `NSToolbar`，包含侧边栏开关、列表/网格切换、刷新、详情区开关、大图控制、缓存容量、导入目录和搜索框
- 联网读取 4KHD 站点栏目
  - 最新
  - 推荐
  - Cosplay
  - 写真
  - 收藏
- 中栏支持列表 / 网格切换
- 图集列表和网格展示封面、标题、图片数量、页数、收藏状态和缓存状态
- 后台打开真实详情页并提取图片地址
- 右侧大图浏览器
  - 上一张 / 下一张切换
  - 触控板缩放
  - 放大后触控板平移
  - 以鼠标位置为中心缩放
  - 实际大小显示
  - 窗内大图模式
  - 大图模式下可隐藏顶部工具栏和底部缩略图栏
- 底部缩略图胶片条，支持自动翻页加载
- 收藏图集，并持久保存详情页链接
- 本地图片目录导入、扫描、搜索、列表/网格浏览
- 本地图片详情浏览、Quick Look、Finder 定位
- 本地详情页解析缓存
  - 已收藏图集永久缓存
  - 未收藏图集缓存 7 天
- 支持保存原图
- 区分推荐内容和广告内容的数据模型
- 使用 Nuke 负责图片加载、缓存和请求优先级

## 截图

发布到 GitHub 时，可以把截图放在这里：

```text
docs/screenshots/main-window.png
docs/screenshots/fullscreen-viewer.png
```

## 架构思路

```text
4KHD 在线页面
    -> 列表解析器
    -> 隐藏详情页解析器
    -> 标准化图片地址
    -> Nuke 图片加载管线
    -> AppKit 原生图片浏览界面
```

主要模块：

- `4KHD/App/4KHDApp.swift`
  AppKit 应用入口，使用 `NSApplicationDelegate`、`NSWindowController` 和原生 `NSToolbar` 创建主窗口。

- `4KHD/Shell/WorkspaceShell.swift`
  使用 `NSSplitViewController` 管理三栏工作区、侧边栏、详情区开合和大图模式。

- `4KHD/Shell/WorkspaceModuleRegistry.swift`
  统一模块接入面，由模块提供 AppKit `NSViewController`。

- `4KHD/Modules/4KHDGallery/`
  在线图库模块，包含站点列表解析、详情页解析、收藏桥接、中栏 AppKit 列表/网格和右侧详情浏览。

- `4KHD/Modules/LocalLibrary/`
  本地图片模块，包含目录导入、metadata 读取、中栏 AppKit 列表/网格和右侧详情浏览。

- `4KHD/Modules/Favorites/`
  收藏记录与收藏分组能力。

- `4KHD/Shared/Services/RemoteImageView.swift`
  封装 Nuke 图片加载 pipeline 和本地图片缓存，用于封面、缩略图和大图显示。

## 运行环境

- macOS
- Xcode
- Swift
- AppKit
- Swift Package Manager
- 可访问 `https://www.4khd.com` 的网络环境

当前主要依赖：

- [Nuke](https://github.com/kean/Nuke)

## 构建方式

用 Xcode 打开项目：

```bash
open 4KHD.xcodeproj
```

也可以用命令行构建：

```bash
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build
```

## 缓存位置

详情页解析结果会写入用户的 Application Support 目录：

```text
~/Library/Application Support/4KHD/DetailPageCache/pages.json
```

图片数据由 Nuke 图片加载管线继续负责缓存。

## 说明

- 生产代码当前按 `0 SwiftUI` 目标维护；如需验证，可运行 `rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'`。
- 软件依赖 4KHD 当前的网站结构。如果网站 HTML 发生变化，解析规则可能需要调整。
- 软件不会随仓库分发网站图片内容，图片内容在运行时从网站读取。
- 请遵守来源网站的访问规则、内容版权和使用限制。

## 许可证

当前项目尚未选择开源许可证。正式公开发布前建议补充 `LICENSE` 文件。
