# 91porny.com 接入协议快照 — 2026-09-01

本文记录实现 `PornyGallery` 时对公开页面的探查结果。路径与标记字段才是代码契约。

HTML 在 Cloudflare 后面，抽样首页与 `/video/view/{id}` 仍是公开 200。页面上的登录/注册是站点外壳，不是这次抽样条目的播放门。

**不要**伪造 Cookie / JSESSIONID、打登录或验证码接口、反推 `m` 签名、或绕 Cloudflare challenge。公开 HTML 没有 `data-src` 时模块显示不可播放。

## 列表

- 分类：`/video/category/{slug}`，后续 `/video/category/{slug}/{n}`
- v1 使用原站这 14 项（顺序与导航一致）：最近更新、高清视频、最近加精、当前最热、最近得分、非付费、91原创、10分钟以上、20分钟以上、本月讨论、本月收藏、收藏最多、本月最热、上月最热
- 真实卡片：`video-elem` 且 `href="/video/view/{id}"` 或高清分类 `href="/video/viewhd/{id}"`（id 为字母数字）。封面 `background-image: url('//int.ucloud161.xyz/thumb/N.jpg')`，时长 `small.layer`
- 广告卡片走外域（如 `w87434799.vip` + `txdy.mczsok.com` gif），常见 `class="video-elem mb-3"`，必须跳过
- 分页：`ul.pagination`，下一页是 `&raquo;` 链接
- 搜索：`GET /search?keywords=`。按钮上的 `needAuth` 不改变「只读公开 HTML」策略；空结果或没有 `data-src` 就当不可播
- 不做 `/videos`（蝌蚪）和 `/vod`

## 详情与 HLS

- `<video id="video-play" data-src="https://cdn2.jiuse3.cloud/hls/{n}/index.m3u8?t=...&m=...">`，HTML 实体 `&amp;` 要先解码
- 签名查询串会过期，必须在每次播放/下载时现解析，不能缓存死地址
- `/video/category/hd` 卡片走 `/video/viewhd/{id}`。公开页 `data-src` 是共享 `//cdn2.jiuse2.cloud/hlsd/js10/index.m3u8` 预告，不是该条目自己的清单；不要扩 allowlist 去播预告
- 同一 id 的 `/video/view/{id}` 公开页才有带 `t`/`m` 的 `cdn2.jiuse3.cloud/hls/{n}/index.m3u8`。播放/下载解析 `viewhd` 时改请求这个普通观看页
- `/premium` 一类仍可能是会员内容；只播放公开 HTML 里已经出现的、非 `/hlsd/` 的 URL

## 安全门禁

- HTML：仅 HTTPS exact/subdomain `91porny.com`
- 媒体：仅 exact `int.ucloud161.xyz`、`int.qiniuyun37.xyz`，以及 exact/subdomain `jiuse3.cloud`
- 请求保留 Safari User-Agent 和 `https://91porny.com/` Referer
- 重定向必须重新走同一白名单。不要用 `host.contains`

## 产品边界

- 纯视频源：不使用右侧详情栏。双击/右键播放，右键下载。无胶片条、图集分页、尾页推荐
- Cloudflare 验证脚本可能出现在 HTML 末尾；本次用普通 URLSession 能拿到列表。若日后 HTML 变成 challenge 页，应失败可见，而不是接 Knit 的验证窗去绕过
- AVPlayer 自行发起的 HLS 子请求不经过 `OnlineSourcePolicy`
