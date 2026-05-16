# 4KHD 真实数据接入阶段备忘

> 更新时间：2026-04-05
> 目的：记录“从 fixture 演示态进入真实 4KHD 数据优先态”的当前进度

## 当前状态

这一阶段目前已修正为文档主路线：

- 结构数据仍以 `script / fixture` 为主
- 不再把 `URLSession` 直连 4KHD / `i0.wp.com` 当作第一阶段核心能力
- 详情页加载后，由隐藏 `WKWebView` 尝试补采真实标题、分页和图片节点
- 详情图片区已改成“可见 `WKWebView` 正常加载真实详情页，再在同一浏览器上下文里把页面重写成纯图片内容”
- `fixture` 继续作为结构回退

因此当前应用的数据链路已经变成：

```text
Script / Fixture
  -> FourKHDHTMLParser
  -> Models
  -> ViewModel
  -> Native UI
  -> Hidden WKWebView enrich(detail)
  -> Visible WKWebView render(images)

Fallback:
Fixture HTML
```

## 这次改动的关键点

### 1. 路线修正

修正原因：

- 当前真实运行环境下，`URLSession/curl` 对 `4khd.com` 与 `i0.wp.com` 出现 TLS reset
- 这与最初文档判断一致：普通 HTTP 客户端并不适合当第一阶段图片主链路

因此现在重新对齐到原文档：

- 脚本/fixture 管结构
- `WKWebView` 管复杂图片加载与真实浏览器环境补采

### 2. 解析器双模支持

更新：

- `4KHD/Services/DataSource/FourKHDHTMLParser.swift`

现在同时支持：

- fixture 结构：`entry-card / entry-title`
- 真实站点结构：`li.wp-block-post / h2.wp-block-post-title / figure.wp-block-post-featured-image`

详情页解析新增支持：

- `h3.wp-block-post-title`
- `canonical / og:url`
- `page-numbers`
- 主内容区图片链接与图片节点提取

### 3. WebView 补采链路

更新：

- `4KHD/Modules/GalleryLibrary/ViewModel/GalleryBrowserViewModel.swift`
- `4KHD/Services/WebViewBridge/WebViewCoordinator.swift`
- `4KHD/Shared/UI/WebImageGalleryView.swift`

当前能力：

- 详情基础模型先正常落到右侧原生面板
- 隐藏 `WKWebView` 加载真实详情页
- 页面加载完成后注入 JS
- 回传标题、分页和图片节点给原生层
- 如果补采成功，原生详情模型会被覆盖刷新
- 右侧图片区域不再用原生网络图组件直拉图片
- 改为让可见 `WKWebView` 先正常进入真实详情页，再由注入脚本移除站点壳层，只保留图片画廊内容

## 当前仍待验证

你本机运行时，需要重点看这三件事：

1. 列表可继续显示 `Fixture`，这是当前结构回退的预期
2. 点击任一图集后，右侧详情是否会被 `WKWebView` 补采刷新
3. `webview enrich success` 是否出现在日志中

## 下一步

如果本轮验证通过，下一步直接进入：

1. 验证详情区 `WKWebView` 是否能稳定显示真实 4KHD 图片
2. 如果成功，再评估列表封面是否也要接入同样的浏览器辅助策略
3. 最后再建立图片缓存、失败降级与首屏体验优化
