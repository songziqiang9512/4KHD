# misskon.com 页面结构与实现快照

更新日期：2026-08-28。站点 HTML 会变化；源码、回归测试和实时响应优先于本文快照。

## 列表页（首页 / Tag 页 / Top 页）

### 通用结构
```
容器: <div class="post-listing archive-box">
每篇文章: <article class="item-list">
  <div class="post-thumbnail">
    <a href="{detailURL}">
      <img src="data:image/svg+xml,..." data-src="{coverURL}" class="attachment-tie-bigger wp-post-image lazy" />
    </a>
  </div>
  <h2 class="post-box-title">
    <a href="{detailURL}">{Title} (N photos)</a>
  </h2>
  <p class="post-meta">
    <span class="post-views"><i class="fa fa-eye"></i>N </span>
    <span class="post-cats"><i class="fa fa-tags"></i> <a href="https://misskon.com/tag/{tag}/" rel="tag">{Tag}</a></span>
  </p>
</article>
```

### 列表页 URL 规则
- 首页: `https://misskon.com/`
- Tag 页: `https://misskon.com/tag/{tag}/`
- 分页: `https://misskon.com/page/{N}/` 或 `https://misskon.com/tag/{tag}/page/{N}/`
- 搜索: `https://misskon.com/?s={query}`
- Top 30: `https://misskon.com/top30/`（自定义页面模板）
- Top 30 分页: `https://misskon.com/top30/page/{N}/`（**HTML 中无分页元素但 URL 有效**）

### 列表页解析要点
- 封面图使用 `data-src` 属性（lazy loading），`src` 为 SVG 占位符
- 标题中包含图片数量: `(N photos)`
- 详情链接有尾部斜杠: `https://misskon.com/{id}-{slug}/`
- 标准归档页 HTML 中有分页导航（`<span class="current">` 等）
- Top30 等自定义页面模板：HTML 无分页元素，但 WordPress 仍支持 /page/N/ URL。
  解析器通过检测 `articleCount > 12` 自动构造下一页 URL

### 分页规则
- 标准归档：从 HTML 提取 `current` 页号和 `next` 链接
- 自定义模板（top30 等）：无分页 HTML 元素，只有文章数严格大于 12 时才构造下一页
- 单页/无内容：文章数不超过 12 时，不构造下一页 URL

---

## 详情页

```
<h1 class="name post-title entry-title"><span itemprop="name">{Title} (N photos)</span></h1>

<div class="entry">
    <!-- 顶部页码导航 -->
    <div class="page-link">
        <span class="post-page-numbers current" aria-current="page">1</span>
        <a href="{detailURL}2/" class="post-page-numbers">2</a>
        <a href="{detailURL}3/" class="post-page-numbers">3</a>
        ...
    </div>
    
    <!-- 图片内容 -->
    <p>
        <img class="aligncenter lazy" src="data:image/svg+xml,..." data-src="https://tez.misskon.com/uploads/YYYY/MM/DD/{filename}.webp" alt="..." />
        <br />
        <img class="aligncenter lazy" src="data:image/svg+xml,..." data-src="https://tez.misskon.com/uploads/YYYY/MM/DD/{filename}.webp" alt="..." />
        <br />
        ... (每页约 12 张)
    </p>
    
    <!-- 底部页码导航（与顶部相同） -->
    <div class="page-link">
        <span class="post-page-numbers current" aria-current="page">1</span>
        <a href="{detailURL}2/" class="post-page-numbers">2</a>
        ...
    </div>
</div><!-- .entry /-->
```

### 详情页 URL 规则
- Page 1: `https://misskon.com/{id}-{slug}/` （= detailURL）
- Page N: `https://misskon.com/{id}-{slug}/{N}/`
- 页码导航出现在 entry 内容的顶部和底部，各一个 `<div class="page-link">`

### 详情页解析要点（已实现）
- **关键**: entry 内容有**两个** `<div class="page-link">`，图片夹在中间
- 图片主要使用 `data-src` 属性，`src` 为 SVG 占位符
- **额外支持**: `src` 属性的非 SVG 图片（部分图片可能不使用 lazy loading）
- 图片格式: WebP
- 图片域名: `tez.misskon.com`
- 每页约 12 张图片
- 页码导航中只显示首尾几页（如 1 2 3 4），需通过扫描所有 `<a class="post-page-numbers">` 获取实际页数
- `resolvePageURLs` 扫描所有锚标签获取最大页码，构造完整 pageURL 列表
- 渐进式加载：首页先解析，详情 Store 只预取相邻两页；用户接近当前末尾或显式导航时再沿连续页序推进，失败页移除占位并保留重试入口

---

## MissKonDetailResolver 实现细节

### extractImageURLs 逻辑
1. 定位 `<div class="entry">` 起始位置
2. 在 entry 内查找所有 `<div class="page-link">` 出现位置
3. 若有 ≥2 个 page-link：提取第一个 div 结束标签 → 第二个 div 开始标签之间的内容
4. 若有 1 个 page-link：提取该 div 之后 → entry 结束标记之前的内容
5. 若无 page-link：提取整个 entry 内容
6. 从内容中提取 `data-src` 属性（优先）和 `src` 属性（非 SVG 的回退方案）
7. 图片 URL 必须通过 `OnlineSourcePolicy` 的 HTTPS exact/subdomain allowlist（`misskon.com` / `mrcong.com`），不得用字符串 `contains` 判断来源
8. 按出现顺序去重

### resolvePageURLs 逻辑
1. 找到当前页码（`<span class="post-page-numbers current">`）
2. 扫描所有 `<a class="post-page-numbers">` 获取锚标签中的页码
3. 取 current + anchor 中的最大页码作为总页数
4. 构造 1...maxPage 的 URL 数组（page 1 = baseURL，page N = baseURL + N/）

---

## 与 4KHD.com 的关键差异

| 特性 | 4KHD.com | misskon.com |
|------|----------|-------------|
| 列表项标签 | `<li class="wp-block-post">` | `<article class="item-list">` |
| 封面图属性 | `src` | `data-src` (lazy) |
| 详情链接格式 | `/{slug}.html` | `/{id}-{slug}/` |
| 图片域名 | `pic.4khd.com`, `img.4khd.com` | `tez.misskon.com` |
| 图片数量格式 | `[Size-Nphotos]` | `(N photos)` 在标题中 |
| 详情内容容器 | `<div class="entry-content">` | `<div class="entry">` |
| 详情分页位置 | 仅在底部 | **顶部和底部各一个** |
| 页码标签 | `<li class="numpages">` | `<div class="page-link">` + `<span class="post-page-numbers current">` |
| 分页 URL 格式 | `/{slug}.html/{N}` | `/{id}-{slug}/{N}/` |
| 每页图片数 | ~20 | ~12 |
| 列表页缓存策略 | 离线 JSON(ApifyLibrary) | 实时 HTTP + 内存状态 + 按 section 磁盘缓存 |
| WordPress 主题 | 自定义 Block 主题 | Sahifa 经典主题 |
| 图片 URL 来源 | HTML 优先，必要时 WKWebView fallback | HTML data-src |
| 详情页解析方式 | DetailPageHTMLResolver + DetailImageResolver fallback | MissKonDetailResolver(HTML) |

## 当前扩展能力

- 首页解析 Yet Another Related Posts Plugin（YARPP）容器中的 6 个原站推荐；全部图片页完成后，从最后一张继续向后导航才显示推荐网格。
- MediaFire 短链属于 MissKon 业务 metadata，只写入 `MissKonDetailMetadataCache`，不进入 Shared 的通用详情缓存 schema。
- 详情分页失败会移除该页占位并把该页计入本轮完成状态，其余未处理页面仍可继续；所有页面均失败时显示解析失败并由重试动作重新解析当前图集。
