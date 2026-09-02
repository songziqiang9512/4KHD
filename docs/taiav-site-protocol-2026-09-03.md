# taiav.com 接入协议快照 — 2026-09-03

本文记录实现 `TaiavGallery` 时对公开页面的探查结果。路径、host 与字段才是代码契约。

公开 `URLSession` 能拿到 200 HTML，不是 Cloudflare challenge 页。**不要**接 Knit 验证窗、伪造登录 Cookie、调用购买/积分/签到接口，或接入站点 P2P。

只使用简体入口 `/cn`。不要跟 `/tc`、`/en`。

## 列表

- 影片卡片：`class="movie-card"`，链接 `/cn/movie/{24 位 hex id}`
- 封面：`https://img.storyofthepast.xyz/videos/{YYYYMM}/{DD}/{id}/poster2.jpg|webp`
- 标题优先 `data-full-title`，否则 `img alt`
- 广告常见 `/file/` 封面或外链（如 `enter.javhd.com`），必须跳过
- 首页 `/cn` **没有分页**（`?page=2` 不会给出新卡片）。不能当唯一可翻页信息流
- 分类 4 项（发现页）：无码 / 有码 / 国产AV / 网红主播。URL `https://taiav.com/cn/category/{名}`，后续 `?page=N`，每页约 15 条。下一页是分页里的 `&raquo;`，末页是「尾页」
- 标签 `/cn/tag/{名}` 也可翻页。**不要把标签名单写进仓库**。v1 只做最近更新 + 4 分类
- 搜索：`GET /cn/search?q=`，查询串必须百分号编码；未编码中文会 **400**。分页 href 自带 `q=` 与 `page=`

## 播放与 HLS

观看页 DPlayer/Clappr **没有**内嵌可播 m3u8。公开接口：

```
GET https://taiav.com/api/getmovie?type=1280&id={24hex}
```

无登录返回 JSON：`{"m3u8":"/videos/{date}/{id}/{dir}/index.m3u8?random=...&counts=5&timestamp=...&key=..."}`

- `type=1280` 是页面默认 720P（`var hd = "1280"`）
- 只认 `m3u8` 字段。有 `message` 也忽略。没有 `m3u8` → 不可播放
- 路径必须含当前影片 id，防止串片
- 相对路径拼到 `https://img.storyofthepast.xyz`。不要丢给 `https://taiav.com/videos/...` 再用默认 `Accept: */*`（会回到首页 HTML）
- 签名 query 会过期，每次播放/下载现请求，不缓存死地址
- HLS 是 AES-128 MPEG-TS VOD，`#EXT-X-ENDLIST`，无 discontinuity。KEY 相对 URI，16 字节，host 同封面站。TS 在 `*.snmovie.com`（编号会变）
- 页面有「买完整版」按钮和 `/api/buymovie`，**不要调用**。公开清单已是可封装的 VOD
- 禁止：`/api/buymovie`、`/api2/buydownload`、`/api2/moviedownloadprice`、`/api/checkin`、`/cn/login`。应用下载走现有 HLS 封装，不是站点积分下载

## 安全门禁

- HTML：仅 HTTPS exact/subdomain `taiav.com`
- API：仅 HTTPS exact/subdomain `taiav.com` 且 path 为 `/api/getmovie`
- 媒体：仅 exact `img.storyofthepast.xyz`，以及 exact/subdomain `snmovie.com`
- 不要把镜像写进 allowlist：`bangerspis.xyz`、`linlinverse.com`、`taimadou.com`、`storyofthepast.xyz` 根域
- 请求：Safari User-Agent + `https://taiav.com/cn` Referer
- 不要接 p2pml/WebRTC P2P
- Cloudflare 若变成 challenge 应失败可见，不要接 Knit 验证窗
- AVPlayer 自行发起的 HLS 子请求不经过 `OnlineSourcePolicy`；带 Referer 的播放走现有本机 loopback 代理（与糖心Vlog 同一条解密路径）

## 产品边界

- 纯视频源：不使用右侧详情栏。双击/右键播放，右键下载。无胶片条、图集分页、尾页推荐
- 侧边栏固定：最近更新 + 4 个原站分类。rawValue 同时是路由 itemID
