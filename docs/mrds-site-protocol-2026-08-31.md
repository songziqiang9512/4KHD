# www.mrds66.com 接入协议快照 — 2026-08-31

本文记录实现 `MrdsGallery` 时对原站的实时探查结果。页数是站点内容量快照，会随新增内容变化；路径与标记字段才是代码契约。

站点是 Typecho + Mirages，不是 Knit 的 WordPress/AJAX 栈。普通 HTTPS 请求即可拿到 HTML，没有 Cloudflare challenge。不要信任镜像域名（如 `mrdsw15.com` / `mrds.com`）。

## 列表协议

- 每页约 30 个 `id="post-card-{id}"` 卡片；`article.ad-item` / `ad-card` 必须跳过。
- 首页分页：`/`，后续 `/page/{n}/`。分类分页：`/category/{slug}/`，后续 `/category/{slug}/{n}/`（不是 `/page/n/`）。
- 搜索：`/search/{encodeURIComponent}/`，后续 `/search/{encoded}/{n}/`。`GET /action/api/search?s=` 只返回 `{"total":N}`，不能当列表数据源。
- 封面来自 `loadBannerDirect('https://pic.sbhioa.cn/...')`，偶发双斜杠 `cn//upload_01`，请求前归一成单斜杠。
- 详情入口是 `/archives/{id}/`。
- 分页导航在 `ol.page-navigator`，下一页是 `class="next"`。
- 没有 `?ajax=1` JSON 列表；带该参数仍返回 HTML。

## 侧边栏分类（原站导航顺序）

最近更新 + 20 个分类：mrds 每日大赛、ztds 主题大赛、rstt 热搜吃瓜、xazd 校园学生、blyp 必撸大赛、fctg 反差泄密、mhds 网红黑料、lqdp 猎奇重口、jdsj AV看片、mxwh 明星大赛、smdh 动漫之家、dypd 影视国漫、mtds cos写真、ysds 声控ASMR、czds 寸止挑战、hjds 混剪PMV、tgds 原创投稿、omjp 欧美精品、qwcs 全网参赛、aijc AI剧场。

这些都是互斥路径，不是可组合筛选。应用把它们全部放在侧边栏，不另做工具栏双层筛选。

## 详情、图片与推荐

- 详情页只有一页：`/archives/{id}/`。正文在 `.post-content[itemprop=articleBody]`。
- 可见图是占位 `/usr/plugins/tbxw/zw.png`，真实地址在 `data-xkrkllgl`。
- 尾页推荐来自 `.post-near` 的上一篇/下一篇 `/archives/{id}/`，`title=` 是标题。该块没有封面图；封面从邻篇档案页的 `loadBannerDirect` 读取，没有横幅时用第一张 `data-xkrkllgl`。不要用站点 `og:image`（那是 HTML 站上的 `social.jpg`，过不了媒体 allowlist）。
- 图片 CDN `pic.sbhioa.cn` 需要 Safari User-Agent 和 `https://www.mrds66.com/` Referer。响应 `Content-Type` 是 `binary/octet-stream`，正文是 AES-128-CBC（PKCS7）密文，不是 JPEG/GIF 原文件。浏览器插件用 UTF-8 密钥 `f5d965df75336270` 和 IV `97b60394abc2fbe1` 解密后再显示；应用必须走同一变换，明文才有图片魔数。

## 视频

- DPlayer `data-config` JSON：`"video":{"url":"...m3u8...","type":"hls"}`。
- 清单 host：`hls.piotrt.cn`。分片与 AES-128 key host 会轮换：`ts.syjiaotong.mobi`、`tx.doudou520.online`、`ts.zhixunkeji.xyz`（均带 `auth_key`）。
- 清单含 `#EXT-X-KEY:METHOD=AES-128`，带显式 IV，分片是 MPEG-TS，且有 `#EXT-X-ENDLIST`（VOD）。保存 MP4 时下载 16 字节密钥、按 KEY 行 IV 做 AES-128-CBC 解密，再 concat TS，由共享 `KnitVideoRemux` 按容器无损封装。`auth_key` 必须随 URL 保留。SAMPLE-AES、直播清单、独立音轨仍不能保存。
- AVFoundation 自己发起的变体清单、key 和 TS 子请求不经过 `OnlineSourcePolicy`。这与 Knit 播放链相同，不得宣称全链门禁。

## 安全门禁

- HTML：仅 HTTPS exact/subdomain `mrds66.com`。
- 媒体：仅 `pic.sbhioa.cn`、`hls.piotrt.cn`、`ts.syjiaotong.mobi`、`tx.doudou520.online`、`ts.zhixunkeji.xyz`。
- 重定向必须重新走同一白名单。不要用 `host.contains`。
