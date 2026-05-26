# misskon.com 页面结构文档

## 列表页（首页 / Tag 页）

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

### 列表页解析要点
- 封面图使用 `data-src` 属性（lazy loading），`src` 为 SVG 占位符
- 标题中包含图片数量: `(N photos)`
- 详情链接有尾部斜杠: `https://misskon.com/{id}-{slug}/`

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

### 详情页解析要点
- **关键**: entry 内容有**两个** `<div class="page-link">`，图片夹在中间
- 图片使用 `data-src` 属性，`src` 为 SVG 占位符
- 图片格式: WebP
- 图片域名: `tez.misskon.com`
- 每页约 12 张图片
- 页码导航中只显示首尾几页（如 1 2 3 4），需通过 URL 模板生成全部页码
- 总页数 = ceil(imageCount / 12)，imageCount 从标题中提取

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
| WordPress 主题 | 自定义 Block 主题 | Sahifa 经典主题 |
