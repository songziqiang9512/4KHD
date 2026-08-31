# 91quanji.com 接入协议快照 — 2026-09-01

本文记录实现 `QuanjiGallery` 时对公开页面的探查结果。路径与标记字段才是代码契约；页数和 CDN 主机会变。

站点自称木瓜视频，列表和观看页抽样为公开 200，未见登录墙。不要做 `makers.jsp` 热门厂商（v1）。

## 列表

- 卡片：`div.item.thumb.thumb--videos` → `watch.jsp?v={id}`，封面 `https://pics.mugua01.cfd/...`，标题 `h5.thumb-spot__title`
- 侧边栏：最近更新 `/`（混合栏目、无有效下一页）、国产精品 `tag.jsp?t=5y9kg97rdzxe`、国产自拍 `tag.jsp?t=649e2zxgw10p`
- 标签分页：不透明 `p=`；当前页是 `<li class="active"><a>N</a>`；下一页是 chevron-right 的 `?t=...&p=...`
- 搜索：`GET /search.jsp?keyword=`；后续页看页面脚本 `nextPage = N`

## 详情与 HLS

- 观看页 `watch.jsp?v=` 使用 DPlayer。播放地址在公开脚本 `eval(I("..."))` 中：UTF-16 code unit XOR `0x80` 后出现 `url: 'https://....m3u8?v=...'`
- 这是页面自带编码，不是登录或签名破解
- 抽样 HLS 父域 `o9hx3f-s8jamrmtps5.sbs`（如 `8017.o9hx3f-s8jamrmtps5.sbs`）。父域轮换后需要扩 allowlist 才能继续播

## 安全门禁

- HTML：仅 HTTPS exact/subdomain `91quanji.com`
- 媒体：仅 exact/subdomain `mugua01.cfd`、`o9hx3f-s8jamrmtps5.sbs`
- 请求保留 Safari User-Agent 和 `https://91quanji.com/` Referer
- 重定向必须重新走同一白名单。不要用 `host.contains`

## 产品边界

- 纯视频源：不使用右侧详情栏。双击/右键播放，右键下载。无胶片条、图集分页、尾页推荐
- AVPlayer 自行发起的 HLS 子请求不经过 `OnlineSourcePolicy`
