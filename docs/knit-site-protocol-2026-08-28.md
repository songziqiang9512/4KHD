# xx.knit.bid 接入协议快照 — 2026-08-28

本文记录实现 `KnitGallery` 时对原站的实时探查结果。页数是站点内容量快照，会随新增内容变化；路径与响应字段才是代码契约。

## 列表协议

- 每页 16 个 `<article class="excerpt">` 卡片。
- AJAX 请求携带 `X-Requested-With: XMLHttpRequest` 并增加 `ajax=1`。
- JSON 返回 `html`、`pagination`、`fallback_articles`；分页字段为 `current_page`、`total_pages`、`has_next`、`next_page` 等。
- 卡片详情地址为 `/article/{id}/`，封面在 `data-original-src`，`play-icon` 表示含视频。
- 搜索第一页 `/search/?s={query}&ajax=1`，后续 `/search/page/{n}/?s={query}&ajax=1`。

## 四分区与互斥筛选路径

应用侧边栏固定为四个入口。原站类型、排行和专题都是互斥路径，不能组合查询；工具栏只在当前侧边栏分区内提供对应的单选项。

| 侧边栏 | 默认筛选 | 工具栏内容 |
|---|---|---|
| 最近更新 | `/` | 最近更新 |
| 妹子图 | `/type/3/`（丝袜美女） | 10 个一级类型；当前一级类型下再提供其相关专题 |
| 排行榜 | `/sort/hot/`（最受欢迎） | 最新发布、最受欢迎、今日热门、3 天热门、本周热门、本月热门 |
| 影片花絮 | `/bits-of-news/` | 影片花絮 |

分页路径规则：

| 内容 | 第一页 | 后续页 |
|---|---|---|
| 最近更新 | `/` | `/page/{n}/` |
| 10 类妹子图 | `/type/{1...10}/` | `/type/{1...10}/page/{n}/` |
| 最新发布 / 最受欢迎 | `/sort/new/`、`/sort/hot/` | `/sort/new|hot/page/{n}/` |
| 今日 / 3 天 / 本周 / 本月热门 | `/rankings/daily|3days|weekly|monthly/` | `/rankings/daily|3days|weekly|monthly/page/{n}/` |
| 影片花絮 | `/bits-of-news/` | `/bits-of-news/page/{n}/` |
| 相关专题 | `/topic/{slug}/` | `/topic/{slug}/page/{n}/` |

`/tag/4111/` 是另一条标签精选路径，不是「影片花絮」，不得替代 `/bits-of-news/`。

### 妹子图一级类型与相关专题

10 个一级类型按原站顺序为：性感美女、清纯美女、丝袜美女、美腿美女、美胸美女、Cosplay、制服诱惑、网络美女、大尺度美女、AI 美女。原站当前为其中 8 类提供 25 个「相关专题」；清纯美女与网络美女当前没有相关专题。

| 一级类型 | 相关专题 |
|---|---|
| 性感美女 `/type/1/` | 内衣美女精选 `/topic/lingerie-beauty/`；美臀美女精选 `/topic/beautiful-hips/`；风骚美女精选 `/topic/provocative-beauty/`；情趣内衣精选 `/topic/sexy-lingerie/` |
| 清纯美女 `/type/2/` | 无 |
| 丝袜美女 `/type/3/` | 白丝美女精选 `/topic/white-silk-stockings/`；黑丝美女精选 `/topic/black-silk-stockings/`；丝袜诱惑精选 `/topic/stocking-allure/`；黑丝诱惑精选 `/topic/black-silk-allure/` |
| 美腿美女 `/type/4/` | 美腿美女精选 `/topic/long-leg-beauty/`；旗袍美女精选 `/topic/qipao-beauty/` |
| 美胸美女 `/type/5/` | 美胸美女精选 `/topic/beautiful-bust/`；巨乳美女精选 `/topic/busty-beauty/`；美乳美女精选 `/topic/meiru-beauty/` |
| Cosplay `/type/6/` | JK 精选 `/topic/jk-highlights/`；雯妹不讲道理 Cosplay 写真合集 `/topic/wenmei-bujiangdaoli-cosplay/`；白丝 Cosplay 精选 `/topic/cosplay-white-silk/`；黑丝 Cosplay 精选 `/topic/cosplay-black-silk/` |
| 制服诱惑 `/type/7/` | 黑丝制服精选 `/topic/black-silk-uniform/`；制服诱惑精选 `/topic/uniform-fantasy/` |
| 网络美女 `/type/8/` | 无 |
| 大尺度美女 `/type/9/` | 白虎福利姬私房视频 `/topic/baihu-fuliji-video/`；大尺度美女精选 `/topic/explicit-beauty/` |
| AI 美女 `/type/10/` | AI 生成图集专题 `/topic/ai-generated-collections/`；AI Porn 图库 `/topic/ai-porn/`；古风 AI 成人图集 `/topic/ancient-style-ai-porn/`；碧蓝航线 AI 美图 `/topic/azur-lane-ai-girls/` |

### 排行榜精确映射

| 工具栏项 | 路径 |
|---|---|
| 最新发布 | `/sort/new/` |
| 最受欢迎 | `/sort/hot/` |
| 今日热门 | `/rankings/daily/` |
| 3 天热门 | `/rankings/3days/` |
| 本周热门 | `/rankings/weekly/` |
| 本月热门 | `/rankings/monthly/` |

## 页数快照

| 入口 | 总页数 |
|---|---:|
| 全部更新 | 1680 |
| 类型 1...10 | 315 / 15 / 206 / 65 / 28 / 586 / 67 / 4 / 212 / 187 |
| 最新 / 热门 | 75 / 75 |
| 今日 / 3 天 / 本周 / 本月 | 518 / 945 / 1647 / 1865 |
| 影片花絮 | 90 |
| “cosplay”搜索 | 63 |

## 图片详情、胶片条与尾页推荐

- 第一页 `/article/{id}/` 返回普通 HTML；后续 `/article/{id}/page/{n}/?ajax=1` 返回 `html + pagination` JSON。
- 当前每个详情分页包含 10 个 `item-image__img`；首页 JSON-LD/配置包含图片总数、总页数、简介和标签。
- 应用只在详情栏或沉浸模式可见时按原页序逐页合并图片；相邻两页是预取预算，但请求沿连续完成前缀逐页串行推进，不会越过仍在途或失败的前序页；JSON/HTML 纯解析在并发执行器完成。底部胶片条使用同一 slot 状态展示已解析图片，并以加载项提示后续分页仍在解析。
- Cloudflare 验证窗口由并发请求共享，但每个等待请求独立登记；请求取消会立即释放自己的等待，最后一个等待取消时同步结束验证会话，避免切换分类后残留到超时。
- 首页原站推荐位于 `#recommend-container > .excerpts > article.excerpt`，沿用列表卡片字段；推荐数量跟随原站，不写死固定项数。
- 全部图片分页完成后，从最后一张继续向后导航才切到推荐网格；向前导航返回最后一张。推荐点击打开其精确 `/article/{id}/` 地址。
- 在线收藏通过 KnitGallery 的 `FavoriteSourceAdapter` 获得同一批推荐，推荐点击仍只由 `WorkspaceAppAssembly` 路由回 KnitGallery，Favorites 不直接依赖该业务模块。

## 视频

- 含视频文章提供 `https://media.knit.bid/play/{hash}.m3u8`；清单中的分片位于 `r2-media.knit.bid`。
- 实测 Safari User-Agent 下 HLS 清单返回 200，分片范围请求返回 206；不带所需 User-Agent 的分片请求可能返回 403。
- 应用以 `AVURLAsset` 设置 Safari User-Agent，并在独立 `AVPlayerView` 窗口播放；播放器画面与详情播放按钮的右键菜单都提供「保存视频为 MP4…」和「拷贝影片源 URL」，复制实际 `.m3u8` 地址。
- 播放器观察当前 `AVPlayerItem.status`：失败时暂停并只提示一次；切换视频或关闭窗口时移除观察、关闭旧提示并释放播放器。应用只在创建 asset 前校验入口 HLS URL，AVFoundation 自行发起的变体清单/分片子请求不会回到 `OnlineSourcePolicy`；全链播放门禁需要自定义资源加载器或本地代理。
- 工具栏「保存」菜单只以详情实际解析出的 `.m3u8` 为启用依据；列表标题的 `nV` 和播放图标只是提示，不能作为可下载真值。
- MP4 保存路径：受信任清单解析 → 顺序下载 MPEG-TS 分片 → AVFoundation passthrough 封装 → 校验可播放性/正时长/视频轨 → 在目标目录原子替换。当前只接受未加密、带 `#EXT-X-ENDLIST`、无 `#EXT-X-MAP`/`#EXT-X-BYTERANGE`/独立音轨/discontinuity 的站点 VOD 契约；取消、失败及下次运行会清理任务临时目录。
- 用户选定目标文件后，视频作为来源无关的 `.video` 单文件任务进入与整图集共用的 `DownloadStore` 串行队列。非模态下载窗口显示分片进度、已下载/估算总大小、整体百分比与平滑速度；封装完成后以最终 MP4 的真实大小校正，平均速度描述 HLS 分片传输阶段。关闭窗口不会中断任务，同一详情的活动视频任务会去重；不同活动任务不能预留同一标准化目标路径。
- 视频保存的主/子清单和 TS 分片若返回 403 或 `cf-mitigated: challenge`，整次保存共用一次 `KnitWebSessionBootstrapper` 验证机会并只重试触发请求一次；同步 Cookie 后仍逐请求执行 media allowlist、最终响应与重定向验证，挑战响应和失败重试的临时响应文件立即清理。清单先下载到临时文件，确认不超过 5 MB 后才以内存映射读取。
- 2026-08-28 真实样本 `239c2cd7dc95f643.m3u8`（12 段）已使用生产下载服务完整保存并通过文件大小、系统可播放性、正时长、视频轨与音轨验证，测试耗时约 39 秒；测试目标与任务临时文件随后均已清理。

## 访问验证

普通 URLSession 请求优先。只有收到 HTTP 403 或 `cf-mitigated: challenge` 时才打开 `WKWebView` 验证面板；页面验证完成后同步 `knit.bid` Cookie 并重试原请求。验证面板的初始 URL、每次主框架导航请求和主框架响应均执行 Knit HTML exact/subdomain allowlist，外域跳转在继续前取消。该流程只承接站点正常验证，不绕过访问控制。
