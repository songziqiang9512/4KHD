# tangxinvlog.app 接入协议快照 — 2026-09-02

本文记录实现 `TangxinGallery` 时对公开页面的探查结果。路径、host 与选择器才是代码契约。不要把标签文案或作者名单写进仓库。

站点是 Astro，走 Cloudflare。应用 UI 使用简体路径 `/`，不走 `/zh-tw/`。

**不要**伪造 Cookie、打登录接口、接第三方 parse API，或把别的站点泄漏的地址拿来播。公开观看页没有当前片播放地址时模块显示不可播放。

## 列表与目录

- 最近更新：`/featured/`，后续 `/featured/2`（不必带尾斜杠）。不要用首页 `/`：它是混排区块、没有分页
- 分类目录：`/tag/`，`ul.tag-cloud`，`span.name` + `span.num`，项进 `/tag/{slug}/`，后续 `/tag/{slug}/2`。`?page=2` 不会翻页
- 作者目录：`/a/`，`ul.artist-cloud`，项进 `/a/{名称}/`（名称可含空格、括号，URL 百分号编码）
- 卡片：`<article class="card">` → `a.cover-link href="/v/{数字 id}/"`，标题常见于 `aria-label`，封面 `https://t.5gcdn.xyz/videos/{id}/cover.jpg`（640×360），时长 `span.duration`，作者 `a.nickname href="/a/{名称}/"`
- 广告常见外域（如 `afengyue.com`），必须跳过
- 分页：优先 `<link rel="next">`，否则 `a.pager-link` 文案含「下一页」。页码 `span.pager-status` 形如 `1 / 143`
- 搜索：`/search/` 是 Pagefind 空壳，不能当列表用。公开 `GET /rss.xml`（约一万条 `<item>`），用 `<title>` / `<link>/v/{id}/` / `<description>` 做本地过滤，结果需要上限

## 详情与 HLS

- 观看：`/v/{数字 id}/`
- `<video id="player" poster="https://t.5gcdn.xyz/videos/{id}/cover.jpg">`
- 当前片地址：`const m3u8 = "https://t.5gcdn.xyz/videos/{id}/index.m3u8"`，JSON-LD 也有 `contentUrl`。解析必须核对路径里的 id，相关条目不得当成当前片
- 相关：`div.related-grid`，卡片标记与列表相同
- 标签：`ul.tags a.tag href="/tag/{slug}/"`
- 清单抽样：AES-128，`#EXT-X-KEY URI="enc.key"`，分片 `segN.ts`，`#EXT-X-ENDLIST`，与封面同 host。媒体请求必须带 `https://tangxinvlog.app/` Referer，否则 Cloudflare 403。CDN 把 `enc.key` 标成 Keynote、`.ts` 标成 Qt linguist。播放走本机 `http://127.0.0.1` 代理：代理带 Referer 拉密钥并解密 TS，清单去掉 KEY 行。不要用自定义 scheme 喂 `.ts`，AVPlayer 会报 CoreMedia `-12881`（custom url not redirect）。保存走现有 MPEG-TS AES-128 链，封装沿用 1.9.0 的 `AVAssetExportPresetPassthrough`。不要按别的脚本假设 `.png` 分片伪装

## 安全门禁

- HTML：仅 HTTPS exact/subdomain `tangxinvlog.app`（含 `/rss.xml`）
- 媒体：仅 exact `t.5gcdn.xyz`
- 请求保留 Safari User-Agent 和 `https://tangxinvlog.app/` Referer
- 重定向必须重新走同一白名单。不要用 `host.contains`

## 产品边界

- 纯视频源：不使用右侧详情栏。侧边栏只固定最近更新 / 分类 / 作者。目录卡片进入子信息流，视频卡片才播放。分类/作者目录用统一固定宽高的标签格，长名字换行
- 相关推荐把当前信息流换成观看页相关列表，可回到侧边栏分类
- Cloudflare 验证脚本可能出现在 HTML 末尾；本次用普通 URLSession 能拿到公开页。若日后变成 challenge 页，应失败可见，而不是接 Knit 的验证窗去绕过
- AVPlayer 自行发起的 HLS 子请求不经过 `OnlineSourcePolicy`
