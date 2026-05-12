# 4KHD

4KHD 是一款 macOS 原生图片浏览软件，用来更稳定、更清晰地浏览 4KHD 网站上的图集内容。它会联网读取网站列表，在后台解析真实详情页，并用原生 SwiftUI 界面展示封面、缩略图、大图、分页、收藏和缓存状态。

这个项目的目标不是把网站页面直接套进一个可见的 WebView，而是把网页解析层隐藏起来，只把最终的图片浏览体验交给原生界面处理。

## 功能特性

- macOS 原生三栏图片浏览界面
- 联网读取 4KHD 站点栏目
  - 最新
  - 推荐
  - Cosplay
  - 写真
  - 收藏
- 中栏常驻搜索入口
- 图集列表展示封面、标题、图片数量、页数、收藏状态和缓存状态
- 后台打开真实详情页并提取图片地址
- 右侧大图浏览器
  - 上一张 / 下一张切换
  - 触控板缩放
  - 放大后触控板平移
  - 以鼠标位置为中心缩放
  - 实际大小显示
  - 全屏看图模式
  - 全屏下可隐藏顶部标题栏和底部缩略图栏
- 底部缩略图胶片条，支持自动翻页加载
- 收藏图集，并持久保存详情页链接
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
    -> SwiftUI 原生图片浏览界面
```

主要模块：

- `4KHD/Core/LibraryStore.swift`  
  管理图集列表、栏目切换、搜索、收藏、详情选择、分页和缓存协调。

- `4KHD/Web/SiteListResolver.swift`  
  解析网站列表页，生成图集条目。

- `4KHD/Web/DetailPageHTMLResolver.swift` 和 `4KHD/Web/DetailImageResolverView.swift`  
  在后台解析详情页，提取真实图片地址和分页链接，不直接显示网站页面。

- `4KHD/Core/DetailPageImageCache.swift`  
  将详情页解析结果写入本地缓存。

- `4KHD/UI/GalleryWorkspaceView.swift`  
  实现三栏主界面、大图画布、底部缩略图条和全屏查看器。

- `4KHD/UI/RemoteImageView.swift`  
  封装 Nuke 图片加载，用于封面、缩略图和大图显示。

## 运行环境

- macOS
- Xcode
- SwiftUI
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
xcodebuild -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
```

## 缓存位置

详情页解析结果会写入用户的 Application Support 目录：

```text
~/Library/Application Support/4KHD/DetailPageCache/pages.json
```

图片数据由 Nuke 图片加载管线继续负责缓存。

## 说明

- 软件依赖 4KHD 当前的网站结构。如果网站 HTML 发生变化，解析规则可能需要调整。
- 软件不会随仓库分发网站图片内容，图片内容在运行时从网站读取。
- 请遵守来源网站的访问规则、内容版权和使用限制。

## 许可证

当前项目尚未选择开源许可证。正式公开发布前建议补充 `LICENSE` 文件。
