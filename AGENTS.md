# 4KHD 顶层开发规范

本文件是 4KHD 项目的顶层开发规范，由 AI 开发助手维护。

适用范围：整个仓库、所有模块、所有结构调整/重构/功能开发/Bug 修复。

## 1. 总体原则

4KHD 的长期方向是建设一个可持续发展的 macOS 原生桌面工作区应用底壳。

1. 底壳独立。2. 模块独立。3. 公共能力独立。
4. 删除任意模块，不应影响其他模块运行。
5. 新增模块，不应要求重写底壳。
6. **所有能用 macOS 系统能力做成的功能，绝不自定义自己画。50 行能搞定的功能绝不写 200 行。**

## 2. 架构

```text
4KHD/
  App/          — 应用入口、场景组装、偏好设置、Inspector、下载管理与独立视频播放窗口
  Shell/        — 工作区底壳、模块路由、三栏布局、侧边栏、工具栏
    Toolbar/      — NSToolbar 实现（WorkspaceToolbarHost）
    Immersive/    — 窗内大图模式控制器
    WorkspaceLayout/ — 侧边栏展开状态
  Shared/       — 跨模块可复用能力
    Platform/     — 系统桥接（键盘、QuickLook、壁纸设置、Inspector、CoalescingQueue、NSView/AppKit 扩展）
    Services/     — 图片缓存、远程图片加载、Cookie 桥接、统一图集/单文件下载队列
    State/        — 详情区状态、胶卷条可见性
    UI/           — 瀑布流布局、缩略图卡片、缩放图片视图、RemoteImageView、缩略图预取控制器
      Detail/       — 详情区覆盖层组件
  Modules/      — 业务模块实现
    4KHDGallery/  — 4KHD.com 在线图库模块
    LocalLibrary/ — 本地图片模块
    Favorites/   — 收藏记录模块
    MissKon/     — misskon.com 在线图库模块
    Wallhaven/   — wallhaven.cc 在线壁纸模块
    KnitGallery/ — xx.knit.bid 图片与视频图库模块
    MrdsGallery/ — www.mrds66.com 每日大赛图库模块
    QuanjiGallery/ — 91quanji.com 木瓜视频模块
    PornyGallery/ — 91porny.com 视频模块
    TangxinGallery/ — tangxinvlog.app 糖心Vlog 视频模块
```

### 模块内部结构

每个业务模块应遵循：`Domain / State / Services / UI` 分层。

- `Domain` — 数据模型
- `State` — Store、交互控制器、偏好设置
- `Services` — 网络请求、解析、缓存
- `UI` — NSViewController、NSView、布局

### 约束

1. `App` 只放应用入口与场景组装
2. `Shell` 只放工作区底壳、模块路由、共享布局容器
3. `Shared` 只放至少两个模块使用的通用能力，不带强业务语义
4. `Modules` 只放业务模块实现，模块间不直接依赖
5. **生产代码 `0 SwiftUI`** — 不得引入 `import SwiftUI`、`NSHostingController`、`NSViewRepresentable`、`AnyView`

## 3. 当前模块

| 模块 | 名称 | 说明 |
|------|------|------|
| 在线图库 | `4KHDGallery` | 4KHD 网站栏目浏览、详情页解析、图片提取 |
| 在线图库 | `MissKon` | misskon.com 标签/热门浏览、详情 HTML 解析、渐进式图片加载 |
| 在线图库 | `Wallhaven` | wallhaven.cc API v1 搜索浏览、分类/排序/比例/分辨率筛选、纯度门控、上传者浏览、本地收藏、详情缓存 |
| 在线图库 | `KnitGallery` | xx.knit.bid 四分区浏览、分类相关专题/排行筛选、AJAX 分页、渐进式详情、尾页推荐与独立 HLS 视频播放 |
| 在线图库 | `MrdsGallery` | www.mrds66.com Typecho 分类浏览、详情 `data-xkrkllgl` 图片、尾页相邻推荐与加密 HLS 播放（不保存 MP4） |
| 在线视频 | `QuanjiGallery` | 91quanji.com 木瓜视频：公开列表/标签/搜索、无右侧详情栏，双击播放，XOR 解码 HLS |
| 在线视频 | `PornyGallery` | 91porny.com 十四分类浏览与搜索，无右侧详情栏；公开 `data-src` HLS 才播放；不绕过登录 |
| 在线视频 | `TangxinGallery` | tangxinvlog.app 糖心Vlog：侧边栏最近更新/分类目录/作者目录，标签与作者运行时从 `/tag/`、`/a/` 解析；无右侧详情栏 |
| 本地图片 | `LocalLibrary` | 本地目录导入、扫描、metadata 读取 |
| 收藏 | `Favorites` | 统一收藏入口：跨模块汇总（4KHD/MissKon/Wallhaven/爱妹子/每日大赛/木瓜视频/91PORNY/糖心Vlog），按来源筛选，列表/网格 + 信息卡详情，独立于业务模块 |

## 4. 共享能力清单

| 组件 | 路径 | 用途 |
|------|------|------|
| `WorkspaceTableView` | `Shared/UI/` | 统一 NSTableView 基类（menu、keyDown、live resize） |
| `WorkspaceCollectionView` | `Shared/UI/` | 统一 NSCollectionView 基类（hover、tracking area、keyDown） |
| `WorkspaceZoomableImageView` | `Shared/UI/` | 可缩放图片视图基类（pinch zoom、fit、reset） |
| `WorkspaceThumbnailWaterfallLayout` | `Shared/UI/` | 瀑布流布局 |
| `WorkspaceThumbnailGridCardView` | `Shared/UI/` | 缩略图卡片视图（图片+标题默认显示+高亮+hover 描边缩放） |
| `WorkspaceThumbnailPrefetchController` | `Shared/UI/` | 缩略图预取调度器（可见区附近智能预取） |
| `RemoteImageView` | `Shared/UI/` | 共享远程图片视图（Nuke 加载、占位符、aspectFill/Fit、同步缓存命中） |
| `DetailOverlayChromeView` | `Shared/UI/Detail/` | 详情区覆盖层圆角背景 |
| `DetailNavigationButton` | `Shared/UI/Detail/` | 详情区导航按钮（圆形毛玻璃） |
| `DetailRecommendationsView` | `Shared/UI/Detail/` | 4KHD/MissKon/KnitGallery/MrdsGallery/收藏共用的图集尾页推荐网格 |
| `RemoteImagePipeline` | `Shared/Services/` | Nuke 图片加载管线（含 thumbnailPrefetcher + detailPrefetcher 分离） |
| `DetailPageImageCache` | `Shared/Services/` | 详情页图片 URL 缓存（7 天过期，500/800 容量限制） |
| `OnlineGalleryRecommendation` | `Shared/Services/` | 跨在线源通用的推荐图集值模型 |
| `OnlineSourcePolicy` | `Shared/Services/` | 在线源 HTTPS、host allowlist、重定向与媒体 URL 统一门禁 |
| `RemoteImageURLAspectRatio` | `Shared/Services/` | 从已知图片 URL 参数提取通用宽高比 |
| `DownloadStore` | `Shared/Services/Download/` | 图集与单文件任务共用的下载队列（最多 2 个并行）、取消、视频分片暂停续传、失败重试、进度和完成状态 |
| `AlbumDownloadOrchestrator` | `Shared/Services/Download/` | 来源无关的图集分页解析、图片落盘和逐项结果汇总 |
| `SingleFileDownloadSource` | `Shared/Services/Download/` | 由业务模块注入实际传输实现的来源无关单文件下载契约 |
| `SharingPresenter` | `Shared/Platform/` | 系统分享面板弹出 |
| `WorkspaceKeyboardHandler` | `Shared/Platform/` | 键盘事件分发 |
| `WorkspaceCoalescingQueue` | `Shared/Platform/` | 合并高频刷新 |
| `WorkspacePullToRefresh` | `Shared/Platform/` | 列表/网格下拉刷新（运行时挂 `NSRefreshController`，旧 SDK 编译通过、旧系统 no-op） |
| `FilmstripVisibilityController` | `Shared/State/` | 胶卷条显示/隐藏动画状态 |
| `WorkspaceDetailPaneController` | `Shared/State/` | 详情窗格展开/收起 |
| `OnlineVideoGalleryStore` | `Shared/State/` | 木瓜视频 / 91PORNY / 糖心Vlog 共用的视频列表与 HLS 解析状态 |
| `OnlineVideoFeedViewController` | `Shared/UI/` | 视频模块列表/网格；双击和右键播放/下载，无图集语义 |

## 5. 变更优先级

1. 先保持底壳稳定
2. 再保证模块可独立维护
3. 再抽共享能力
4. 最后才考虑更大规模重构

## 6. 文档维护

结构方向发生实质变化时，必须同步更新 `AGENTS.md`、`README.md` 和 `docs/ai-handover-*.md`。

## 7. 当前状态与开发注意事项

### 统一收藏模块（我的收藏）

- 侧边栏「我的收藏」是「本地」分组内的子节点（紧跟「我的图片」），工具栏按来源筛选（全部/4KHD/MissKon/Wallhaven/爱妹子/每日大赛/木瓜视频/91PORNY/糖心Vlog，rawValue 作路由 itemID）
- 交互与 MissKon/4KHD 完全一致：瀑布流网格（共享 `WorkspaceThumbnailWaterfallLayout` + `WorkspaceThumbnailGridCardView`，间距 8/10/12）、列表行、单击选中/双击开详情、hover 高亮、方向键、右键菜单、搜索高亮、列数调整。木瓜视频/91PORNY/糖心Vlog 收藏例外：双击或回车直接播放，右键提供「播放」「下载视频」，不打开右侧详情栏
- 详情区是大图查看区（缩放/上张下张/计数/胶片条/沉浸模式），由 `FavoritesDetailStore` 统一 slot 模型驱动；具体来源的解析与请求配置由 App 组装层注册 `FavoriteSourceAdapter`，Favorites 模块不得直接依赖 Gallery/MissKon/Wallhaven/KnitGallery/MrdsGallery/QuanjiGallery/PornyGallery/TangxinGallery 的具体类型
- **详情能力必须与来源模块同源**：`FavoriteSourceAdapter` 负责注入图片分页、推荐、请求配置、详情 metadata、来源内导航和可选视频动作。4KHD/MissKon/KnitGallery/MrdsGallery 收藏继续使用原站解析、胶片条和页尾推荐；木瓜视频/91PORNY/糖心Vlog 收藏 `playsFromFeed`，`navigationMode: .sourceRecords`，无详情栏、胶片条与推荐。Gallery 解析仍保留原模块的 WebKit fallback，关闭详情时必须取消并释放等待中的 continuation
- **选择身份与空状态**：列表/网格选择以标准化 `detailURL` 为主键，不得只比较可能跨来源冲突的站点 raw ID；切换到空筛选、删除当前或最后一条收藏时必须同步修正选择并清空旧详情、推荐、视频和工具栏状态
- **KnitGallery 视频一致性**：收藏详情解析到真实 HLS 后显示「播放视频」，空格键可播放，播放按钮及独立播放器的右键菜单均同时提供保存 MP4 与复制影片源 URL，工具栏「保存」菜单也可保存 MP4；播放和保存均经 App 组装层复用 KnitGallery 原生实现，Favorites 不直接依赖播放器或下载器类型。未解析到受信任视频源时必须禁用菜单；不同视频可进入共享下载队列，同一图集的活动任务由 `DownloadStore` 去重
- **MrdsGallery 视频一致性**：收藏详情解析到真实 HLS 后显示「播放视频」，空格键可播放；播放按钮、独立播放器和工具栏「保存」均提供保存 MP4 与拷贝源 URL。站点清单是 AES-128 MPEG-TS VOD：下载密钥后按 KEY 行 IV 解密每个 TS，再走与爱妹子相同的无损封装。`FavoriteVideoActions.canSaveAsMP4 = true`。未解析到受信任视频源时必须禁用菜单
- **Wallhaven 一致性**：收藏详情按同来源收藏记录导航，加载原图与完整 metadata，支持等待原图解析完成后设为壁纸；上传者入口必须在应用内路由到 Wallhaven 上传者作品，不得跳到外部网页或退化为封面图
- **分页顺序**：收藏适配器必须声明来源真实页容量（4KHD 20、MissKon 12、KnitGallery 10、Wallhaven 1、MrdsGallery 单页容量=记录图片数、木瓜视频/91PORNY/糖心Vlog 1）；详情预取预算最多覆盖相邻两页，但请求必须沿连续完成前缀逐页串行推进。后页先返回或解析失败时不得跳过缺口、误判完成或提前进入推荐；再次翻页、点击失败状态或选择失败占位必须能重试。初始占位窗口最多 1,000 张，窗口外页面在推进到末端后继续插入；来源声明页数最多 500 页
- **来源判定必须用 detailURL host**（`FavoriteSource.source(for:)`），`FavoriteRecord.sourceID` 不可靠；封面/大图的防盗链请求配置从对应 `FavoriteSourceAdapter` 获取
- **历史封面仍需重新门禁**：从磁盘恢复或旧版本迁移的 `coverURL` 在列表、网格、预取和详情首图使用前，都必须重新通过所属来源的媒体 allowlist；不能因记录已经持久化就直接信任 URL
- 模块 UI 直接观察 `FavoritesStore.favorites`（`FavoritesModuleStore.visibleRecords` 是计算属性），不要加回 `onFavoritesChanged` 链路
- Gallery/MissKon/KnitGallery/MrdsGallery 来源的收藏项支持「保存整个图集」和「保存当前图片」；Wallhaven 收藏项无图集下载
- Gallery/MissKon/KnitGallery/MrdsGallery 来源的收藏详情在最后一张后继续导航会显示推荐；推荐数据仍经 source adapter 注入，跨模块跳转只由 `WorkspaceAppAssembly` 路由，Favorites 不得直接依赖业务模块
- MissKon 收藏详情通过来源无关的外部动作模型显示 MediaFire 入口；该业务 metadata 仍只由 MissKon 缓存拥有，不得把 URL 字段塞进 Favorites 或 Shared 的通用缓存 schema

### MissKon 模块

- 核心链路完整：列表/网格、分页、搜索高亮+debounce、收藏、Inspector、磁盘列表缓存
- **渐进式详情加载**：`prepare(item:)` 生成占位 slot → `resolve(item:)` 仅加载第一页 + 预取 2 页 → 用户翻到尾部触发 `ensureNextDetailPageLoadedIfApproachingEnd` → 按需加载后续页
- **胶片条占位**：`imageCount > 0` 时预生成精确数量占位 slot；页面解析后 `mergeResolvedPage` 替换 knownURL
- **失败页处理**：失败页占位 slot 自动移除；全部失败显示"解析失败"重试按钮
- **分页阈值**：fallback 猜测使用 `articleCount > 12`（top30 等无显式分页标签）
- **缓存修复**：`restoreSectionCache` 在 `cachedNextPageURLs[section] == nil` 时自动触发刷新
- **业务缓存归属**：MediaFire 等 MissKon 专属详情 metadata 只存入 `MissKonDetailMetadataCache`，不得写回 Shared 的 `DetailPageImageCache` schema
- **详情区封面优先**：打开详情时查 Nuke 内存缓存（4096px → 512px 回退），命中直接显示不闪烁
- **尾页推荐**：全部详情页加载完成后，最后一张继续向后导航显示原站推荐；当前原站固定 6 项，宽详情区 3×2、窄详情区 2×3，点击进入对应 MissKon 图集

### Wallhaven 模块

- 侧边栏分组与入口标题均为 `Wallhaven`（不再使用「在线壁纸」或「浏览」）
- API Key 存储改用 **UserDefaults**（原 Keychain 已移除，避免每次启动弹授权窗）
- **列表请求状态机**：`beginListRequest()` 每请求独立 token → await 后写入前 guard `listRequestToken + section/query` → 旧 Task 不能清新状态
- **上传者浏览**：参数快照化（username/purity/apiKey 在 Task 创建前捕获）→ 身份校验（`uploaderUsername == requestUsername`）→ HTML fallback 支持 `data-wallpaper-id` + `href="/w/{id}"`
- **refresh 模式路由**：`refreshFromNetwork` 自动判断当前模式（uploader/search/favorites/browse）并路由到正确的刷新路径
- **工具栏**：独立 `onlineSave`/`onlineInfo` 按钮（与 Wallhaven 布局统一），+/- 图标交换（minus=更多列=缩小）
- **详情区封面优先**：`setImageURL` 同步查 Nuke 缓存，命中直接显示

### 4KHDGallery 模块（参考实现）

- 在线模块参考实现；网格列数 2-6、列表/网格切换保留位置
- **工具栏**：独立保存/信息按钮（`onlineSave`/`onlineInfo`），与 Wallhaven 布局对齐
- **键盘交互**：Escape 清搜索、Enter 打开详情
- **底部重试**：footer 点击重试，错误显示红色 "errorMessage — 点击重试"
- **搜索高亮**：列表/网格均支持 `activeSearchQuery` 高亮
- **收藏下一张按钮**：`imageCount == 0` 时回退用 `loadedImageSlots.count` 判断
- **尾页推荐**：解析详情首页的原站推荐卡片；最后一张继续向后导航显示共享推荐网格，点击直接打开对应 4KHD 图集

### KnitGallery 模块

- **侧边栏四分区**：固定为「最近更新 / 妹子图 / 排行榜 / 影片花絮」；进入「妹子图」默认「丝袜美女」，进入「排行榜」默认「最受欢迎」，影片入口必须是 `/bits-of-news/`，不能用 `/tag/4111/` 代替
- **工具栏筛选**：「妹子图」提供原站 10 个一级类型，并只为当前一级类型显示其「相关专题」；10 类合计 25 个专题。「排行榜」精确提供「最新发布 / 最受欢迎 / 今日热门 / 3 天热门 / 本周热门 / 本月热门」6 项。所有筛选都是互斥路径，不得伪装成可组合标签
- **列表分页**：列表统一请求 `?ajax=1` 并携带 `X-Requested-With: XMLHttpRequest`，以响应 `pagination.next_page` 生成下一页；搜索后续页使用 `/search/page/{n}/?s=...`
- **详情体验**：与 4KHD/MissKon 一致，提供缩放大图、上/下张、计数、底部胶片条和沉浸模式；第一页普通 HTML，后续 `/article/{id}/page/{n}/?ajax=1`，按原页序逐页合并并按需加载。只有详情栏或沉浸模式真正可见时才启动解析；相邻两页属于预取预算，但必须沿连续完成前缀逐页串行请求，不得跨过在途或失败的前序页
- **线程边界**：网络和 Cloudflare 验证 UI 留在 MainActor；验证 waiter 必须响应请求取消，最后一个 waiter 取消时结束验证会话；JSON 解码、HTML 正则与推荐容器扫描必须经 `@concurrent nonisolated` 解析函数执行，纯 Knit 值模型保持显式 `nonisolated + Sendable`
- **尾页推荐**：详情首页解析 `#recommend-container` 的原站推荐；全部图片页完成后，从最后一张继续向后导航才显示推荐网格，向前返回最后一张。推荐点击进入精确 KnitGallery 图集；在线收藏通过 `FavoriteSourceAdapter` 接收同一推荐数据，再由 `WorkspaceAppAssembly` 路由
- **视频**：解析 `media.knit.bid` HLS 清单；使用 App 层长期持有的独立 `KnitVideoPlayerWindowController` + `AVPlayerView`，不得把播放器嵌进图片详情或引入 SwiftUI；详情「播放视频」按钮、独立播放器画面及收藏详情的右键菜单必须同时提供「保存视频为 MP4…」和「拷贝影片源 URL」，复制实际 HLS 地址。播放器必须观察当前 `AVPlayerItem.status`，失败时只显示一次原生错误提示，切换视频或关闭窗口时撤销观察、保存动作并释放旧播放器
- **视频保存**：工具栏「保存」菜单仅在当前详情已解析出受信任的 HLS URL 时启用「保存视频为 MP4…」，不得用列表标题里的 `nV`/播放图标代替真实视频源。用户选定目标后，视频必须作为 `.video` 任务进入与整图集共用的 `DownloadStore` 队列（最多 2 个并行）和非模态「下载」窗口；失败或取消可重试，视频还可在分片边界暂停后续传。进度、失败、取消和完成结果只在任务中心呈现，详情图片上方不得常驻分类或保存状态。下载只接受带 `ENDLIST`、无 discontinuity 的 MPEG-TS VOD；`METHOD=AES-128` 先下载 16 字节密钥并按 KEY 行 IV 解密每个 TS，再按容器无损封装。SAMPLE-AES 和其他加密仍拒绝。所有清单/分片/密钥与重定向继续经过对应 source 的 media allowlist。MPEG-TS 用 `AVAssetExportPresetPassthrough` 无损封装（与 1.9.0 每日大赛相同）；已是 MP4/fMP4 则直接安装。安装前验证可播放性、正时长和视频轨；失败或取消必须清理临时文件且不得破坏既有目标文件。未完成的视频分片缓存在 Caches，封装失败重试不重新拉分片。主/子清单先下载到临时文件并在映射到内存前执行 5 MB 上限检查。密钥文件上限 64 字节。Knit 保存遇到 403/`cf-mitigated: challenge` 时最多共享一次 WebKit 验证并只重试触发请求一次；Mrds 没有 Cloudflare，403 直接失败。验证后的清单与每个分片仍重新经过 Cookie、host 和重定向门禁
- **访问验证**：URLSession 普通请求优先；仅收到 403/`cf-mitigated: challenge` 时显示模块专用 WKWebView 验证窗，同步 Cookie 后重试，不做 challenge 绕过。验证 WebView 的初始地址、每次主框架导航请求和主框架响应都必须通过 Knit HTML exact/subdomain allowlist，外域跳转在继续导航前取消
- **安全门禁**：HTML 与媒体仅允许 HTTPS exact/subdomain `knit.bid`；图片与 HLS 请求必须保留 Safari User-Agent，图片继续携带 `https://xx.knit.bid/` Referer
- **原图门禁**：列表封面只作详情解析前的过渡图；详情未解析时不得启用或执行「保存当前图片」，在线收藏同样必须确认当前 slot 已由来源页解析
- **缩略图失败恢复**：列表/网格封面首次失败后冷却 3 秒自动重试一次；后续只允许自然重配且冷却到期后重试，复用/换源/成功/缓存命中必须重置状态，旧 generation 回调不得覆盖新请求
- **当前播放边界**：应用能门禁传给 `AVURLAsset` 的入口 HLS URL，但 AVFoundation 自己发起的变体清单和分片子请求不经过 `OnlineSourcePolicy`；若要对播放链每个子请求做与下载链同等级的 host/重定向审计，需要改为自定义资源加载器或本地代理，不得把当前实现宣称为全链门禁
- 站点分页和入口实测快照见 `docs/knit-site-protocol-2026-08-28.md`

### MrdsGallery 模块

- **侧边栏**：高级模块开关下增加「每日大赛」分组，入口为最近更新 + 原站 20 个分类；分类 rawValue 同时是工作区路由 itemID
- **列表分页**：普通 HTML，无 AJAX JSON。首页 `/` 与 `/page/{n}/`，分类 `/category/{slug}/` 与 `/category/{slug}/{n}/`，搜索 `/search/{encoded}/` 与 `/search/{encoded}/{n}/`
- **详情**：单页 `/archives/{id}/`；图片在 `data-xkrkllgl`，占位图 `/usr/plugins/tbxw/zw.png` 不是原图。只有详情栏或沉浸模式真正可见时才启动解析
- **尾页推荐**：`.post-near` 上一篇/下一篇；最后一张继续向后导航才显示推荐网格。邻篇 HTML 没有封面图，解析详情后并行拉取邻篇档案页，封面优先 `loadBannerDirect`，否则第一张 `data-xkrkllgl`；失败时卡片可以没有封面，不得让整次详情解析失败
- **视频**：解析 `hls.piotrt.cn` HLS（保留 `auth_key` 查询串）；复用 App 层 `KnitVideoPlayerWindowController`，传入 `source: .mrds`。站点媒体清单是 AES-128 MPEG-TS VOD（`#EXT-X-ENDLIST`），密钥和 TS 分片 host 会在 `ts.syjiaotong.mobi` / `tx.doudou520.online` / `ts.zhixunkeji.xyz` 间轮换。保存 MP4 时下载密钥、按 KEY 行 IV 解密 TS 后再封装；SAMPLE-AES / 无 ENDLIST / 独立音轨等仍拒绝。播放按钮右键同时提供保存 MP4 与拷贝源 URL
- **列表缓存**：侧边栏切换分类时先恢复该分类的内存列表，再后台刷新；网格封面在 Nuke 内存命中时直接绘制，未命中时也不得先清空已有封面再淡入
- **安全门禁**：HTML 仅 HTTPS exact/subdomain `mrds66.com`；媒体仅 `pic.sbhioa.cn`、`hls.piotrt.cn`、`ts.syjiaotong.mobi`、`tx.doudou520.online`、`ts.zhixunkeji.xyz`。不要信任镜像域名。图片请求保留 Safari User-Agent 和 `https://www.mrds66.com/` Referer
- **图片解密**：`pic.sbhioa.cn` 正文是 AES-128-CBC 密文（站点前端同一密钥/IV）。列表、详情、胶片条、保存和整图集下载都必须先解密再解码或落盘；已是 JPEG/GIF/PNG/WebP 魔数的字节原样使用
- **原图门禁**：列表封面只作详情解析前的过渡图；详情未解析时不得启用「保存当前图片」
- 站点分页和入口实测快照见 `docs/mrds-site-protocol-2026-08-31.md`

### QuanjiGallery 模块（木瓜视频）

- **侧边栏**：高级模块开关下「木瓜视频」分组：最近更新 `/`、国产精品 `tag.jsp?t=5y9kg97rdzxe`、国产自拍 `tag.jsp?t=649e2zxgw10p`。rawValue 同时是路由 itemID。v1 不做热门厂商/`makers.jsp`
- **列表**：公开 HTML 卡片 `thumb--videos` + `watch.jsp?v=`；封面 `pics.mugua01.cfd`。标签页分页是不透明 `p=`，下一页来自 chevron。搜索 `/search.jsp?keyword=`，后续页用页面里的 `nextPage`
- **无详情栏**：`showsDetailPane: false`。双击/回车/右键「播放」解析 HLS 后打开独立播放窗口；右键「下载视频」进入共享下载队列。工具栏不显示详情/沉浸/重置缩放
- **HLS**：写在公开页 `eval(I("..."))` 里，UTF-16 code unit XOR `0x80` 后取 `url: '...'`。这是页面编码，不是登录绕过
- **视频**：复用 App 层 `KnitVideoPlayerWindowController`，`source: .quanji`。保存 MP4 走 `KnitVideoDownloadService`（无 Knit Cloudflare 验证）
- **安全门禁**：HTML 仅 HTTPS exact/subdomain `91quanji.com`；媒体仅 `mugua01.cfd` 与 `o9hx3f-s8jamrmtps5.sbs` 的 exact/subdomain。不要用 `host.contains`
- 站点分页和入口实测快照见 `docs/quanji-site-protocol-2026-09-01.md`

### PornyGallery 模块（91PORNY）

- **侧边栏**：高级模块开关下「91PORNY」分组，入口为原站 14 个 `/video/category/{slug}`。不做 `/videos` 蝌蚪和 `/vod`
- **列表**：只收 `/video/view/{id}` 与高清分类 `/video/viewhd/{id}` 卡片，跳过外域广告 gif。封面多为 `//int.ucloud161.xyz/thumb/`。分类分页 `/video/category/{slug}/{n}`，下一页来自 `&raquo;`。搜索 `/search?keywords=`
- **无详情栏**：`showsDetailPane: false`。双击/回车/右键「播放」现解析公开页再打开独立播放窗口；右键「下载视频」进入共享下载队列
- **HLS**：公开页 `<video id="video-play" data-src="...m3u8?t=&m=">`。`/video/viewhd/{id}` 公开页只有共享 `/hlsd/` 预告，播放/下载改解析同一 id 的 `/video/view/{id}`；没有可播 `data-src` 仍提示不可播放。**不得**伪造 Cookie、打登录接口或绕 Cloudflare
- **视频**：复用 App 层播放器，`source: .porny`。签名 `t`/`m` 会过期，每次播放/下载现解析。AVPlayer 子请求仍不经过 `OnlineSourcePolicy`
- **安全门禁**：HTML 仅 HTTPS exact/subdomain `91porny.com`；媒体仅 exact `int.ucloud161.xyz`、`int.qiniuyun37.xyz` 与 exact/subdomain `jiuse3.cloud`
- 站点分页和入口实测快照见 `docs/porny-site-protocol-2026-09-01.md`

### TangxinGallery 模块（糖心Vlog）

- **侧边栏**：高级模块开关下「糖心Vlog」分组，只固定 3 项：最近更新 `/featured/`、分类目录 `/tag/`、作者目录 `/a/`。不要把标签或作者枚举写进仓库；运行时从目录页解析。深链 itemID `tag:{slug}` / `author:{name}` / `related:{id}` 不出现在侧边栏树里，但 `normalizeRoute` 必须识别
- **列表**：首页最新用 `/featured/`（不要用无分页的 `/`）。卡片 `article.card` + `/v/{数字 id}/`，封面 `t.5gcdn.xyz/videos/{id}/cover.jpg`。分类/作者目录双击进入子信息流，不是播放；目录页没有封面，用统一固定宽高的标签格（长名字换行），而不是无图大卡片或竖向列表。搜索走公开 `/rss.xml`（Pagefind 空壳不可用），结果上限 200
- **无详情栏**：`showsDetailPane: false`。视频卡片双击/回车/右键播放；右键还可打开作者主页、分类和相关推荐。目录卡片只有「打开」
- **HLS**：公开观看页 `const m3u8 = "https://t.5gcdn.xyz/videos/{id}/index.m3u8"`，必须命中当前路径 id，不得拿相关条目的地址。AES-128 MPEG-TS VOD，分片 `.ts`。**不得**伪造 Cookie、打登录接口、接第三方 parse
- **视频**：复用 App 层播放器，`source: .tangxin`。媒体 CDN 无 Referer 会 403。播放走本机 `http://127.0.0.1` 代理（带 Safari UA 与 `https://tangxinvlog.app/` Referer），代理拉密钥并解密 TS，清单去掉 `EXT-X-KEY`。不要用自定义 scheme 喂 `.ts`（AVPlayer `-12881`）。保存 MP4 走 `KnitVideoDownloadService`（无 Knit Cloudflare 验证），封装与 1.9.0 相同：concat TS 后 `AVAssetExportPresetPassthrough`
- **安全门禁**：HTML 仅 HTTPS exact/subdomain `tangxinvlog.app`；媒体仅 exact `t.5gcdn.xyz`
- 站点分页和入口实测快照见 `docs/tangxin-site-protocol-2026-09-02.md`

### 设置面板

- **布局**：一个统一切换选项同时控制 4KHD/MissKon/Wallhaven/KnitGallery/MrdsGallery/QuanjiGallery/PornyGallery/TangxinGallery/本地图库的列表/网格
- **缓存上限**：在线缓存容量选择（512MB-4GB/无限制）
- **清除缓存**：一键清除 Nuke 图片缓存、详情页缓存、MissKon/Wallhaven 模块缓存、本地缩略图缓存、临时文件
- **侧边栏**：开关控制 4KHD/MissKon/KnitGallery/MrdsGallery/QuanjiGallery/PornyGallery/TangxinGallery 模块显示
- **收藏备份**：导出必须覆盖 `FavoritesStore` 中全部合法来源记录（含 KnitGallery/MrdsGallery/QuanjiGallery/PornyGallery/TangxinGallery 全字段）；导入只接受通过对应 `OnlineSourcePolicy` HTTPS 门禁的来源详情 URL。重复 `detailURL` 不得崩溃，首次位置保持稳定、后项内容覆盖
- 全部中文化

### 辅助窗口

- **下载窗口**：使用普通、非模态 `NSWindow` 作为图集与视频的统一任务中心；关闭窗口只隐藏界面，不中断队列。窗口标题是唯一标题，内容区顶部只显示任务摘要与批量操作；每个任务在系统进度条下方等宽显示已下载/总大小、整体百分比和当前速度，完成后显示精确落盘大小与平均速度。图集按单图落盘、视频按 HLS 分片完成采样并平滑速度；运行中的图集/视频总大小允许标记为估算值，视频封装完成后必须用最终 MP4 大小校正。活动单文件任务必须预留标准化目标路径，拒绝第二个任务无确认写入同一文件，并在完成、失败或取消时释放预留。失败和取消的任务提供重试；视频任务可暂停并在分片边界续传，暂停行同时保留取消。清除已完成只移除成功任务，不得动进行中、暂停、失败或取消的任务。空状态、任务类型、目标位置、取消、暂停、重试与清理操作均使用系统控件和语义色
- **信息窗口**：各模块共用一个 App 层 Inspector；固定来源标题区，下方使用可滚动的动态分组 `NSGridView`，缺失字段整行省略。关闭或最小化后必须停止观察与本地 metadata 读取；未选择项目时信息按钮禁用

### 已知 UI 边界

- 顶部系统工具栏在部分三栏/详情栏状态下仍可能丢失 scroll-edge 半透明背景，悬停或窗口失焦后恢复。正确目标是让内容继续穿过系统工具栏下方并由 AppKit 提供背景；不得用 safe-area 截断、自绘工具栏背景、hover 监听或全窗材质层宣称解决。后续若继续处理，必须先用最小可复现窗口确认 `NSSplitViewController`、详情预览和 scroll-edge ownership

### 全局约束

- 修改 Shell 集成任何模块时，先搜索 `case .模块名` 覆盖所有 switch
- 工具栏展示能力统一声明在 `WorkspaceModuleDescriptor.presentation`；新增模块先补 descriptor profile，不要在 `WorkspaceToolbarHost` 追加 moduleID 条件链。纯视频源设 `showsDetailPane: false`
- 工具栏不再放刷新按钮；原位置显示当前模块名或分类/标签名（`locationTitle`）。列表与网格用 `WorkspacePullToRefresh` 下拉刷新。`⌘R` / 菜单「刷新」仍走 `refreshCurrentContent`。不要给胶片条、Inspector、下载窗口或侧边栏加下拉刷新
- 修改任何在线模块时，以 `4KHDGallery` 的状态流和 UI 行为为参考
- 在线模块异步结果必须按请求时的 section/query 回写，不能在 `await` 后直接读当前 section 写状态
- Gallery/MissKon 详情请求合并器必须按 waiter 计数处理取消；最后一个等待者取消时要取消底层网络任务，避免切换详情后继续解析、写缓存或创建 WebKit fallback
- 详情控制器对保存进度/消息只保留一条观察链；不得在每次状态变化时重复注册一次性观察，旧记录的异步保存回调也不得覆盖新详情
- 收藏桥和详情图片解析必须使用 exact/subdomain allowlist，不要用 `host.contains(...)`
- 详情 HTML 截取不要用 `lowercased()` 产生的 `String.Index` 切原字符串；用 `NSString`/`NSRange` 或原字符串 case-insensitive range
- 当前 Xcode 工程包含 `4KHD` App target 和 `4KHDTests` XCTest target；纯逻辑与共享命令行为优先补回归测试
- 在线模块通过 `WorkspaceModuleRegistry.bootstrapModule(_:)` 在首次进入时启动；不要恢复为启动阶段全模块并发刷新
- 在线图片只使用 Nuke DataCache 作为磁盘层，URLCache 不落盘；缓存清理必须同时清内存状态与对应磁盘目录
- **生产代码 0 SwiftUI** — 不得引入 `import SwiftUI`、`NSHostingController`、`NSViewRepresentable`、`AnyView`
- 分页 `nextPageURL` 永远直接用 `page.nextPageURL`，不要加 `newItems.isEmpty ? nil : ...` 条件

常用验证：

```bash
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
```

**改完收尾必须启动 Debug 应用**，方便用户立刻验收；不要只构建不打开。若已有实例在跑，先退出再打开刚编出的 `4KHD.app`。
