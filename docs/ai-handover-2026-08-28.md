# 4KHD AI Handover — 2026-08-28

本文件只保留当前可执行事实；截至 1.8.8 的详细审查、证据和逐项修复结果见历史归档 `docs/optimization-remediation-2026-08-23.md`，爱妹子站点协议见 `docs/knit-site-protocol-2026-08-28.md`。

## 当前状态

- 当前分支 `main`，本批目标版本 1.8.9（build 189），最低系统 macOS 26.4；生产代码纯 AppKit、0 SwiftUI。
- 本批新增 KnitGallery、Favorites 四来源详情一致性、统一图集/视频下载任务中心、收藏备份加固和 Inspector 重排。最终全量 XCTest 共 144 项：143 通过、1 项真实联网 HLS 保存测试按默认门禁跳过、0 失败；Debug 测试构建与 Release 构建通过。生产代码 SwiftUI 禁用扫描、workflow/YAML shell 静态校验与 `git diff --check` 通过。
- 2026-08-28 已使用生产服务单独实测爱妹子首页、视频详情、HLS 清单 200、分片范围请求 206 和一次完整 MP4 保存；这是一份日期限定的样本证据，不代表每次发布都重新探测原站。
- 1.8.9 采用现有受保护 `Build Prerelease` 流程：版本先提交到 `main`，随后由 GitHub Actions 测试、Developer ID 签名、Apple 公证、DMG/staple、Sparkle EdDSA appcast 和不可变 prerelease 完成。按本轮用户要求，正确推送并触发后即移交用户观察，不等待远端任务结束，也不重复下载公开产物。

## 当前架构事实

- `WorkspaceModuleRegistry` 的 descriptor 同时拥有模块 controller factory、route/bootstrap 和 `presentation` 工具栏能力；不要在 ToolbarHost 恢复 moduleID 条件链。
- Favorites 只依赖 `FavoriteRecord`、`FavoriteSource` 和 `FavoriteSourceAdapter` 契约。Gallery/MissKon/Wallhaven/KnitGallery adapter 在 `WorkspaceAppAssembly` 注册；Favorites 内不得直接引用其他业务模块的 bridge/resolver/model。
- `DetailPageImageCache` 只缓存跨站通用图片页；MissKon 专属 MediaFire metadata 归 `MissKonDetailMetadataCache`。
- 4KHD/MissKon/KnitGallery 推荐图集统一使用 `OnlineGalleryRecommendation`、`WorkspaceDetailContentMode` 和 `DetailRecommendationsView`；Favorites 只从 adapter 接收推荐数据，跨模块打开由 App 组装层路由。
- 在线请求统一经过 `OnlineSourcePolicy` 与各模块 request factory：仅 HTTPS、exact/subdomain allowlist；固定来源 URLSession 在发出请求前、跟随每次重定向前和收到最终响应后校验，Gallery fallback 与 Knit 验证 WebView 同时门禁主框架导航请求和响应；不使用 `host.contains(...)`。
- KnitGallery 侧边栏固定为「最近更新 / 妹子图 / 排行榜 / 影片花絮」；妹子图默认丝袜美女并提供 10 个一级类型及当前类型相关专题（合计 25 个），排行榜默认最受欢迎并精确提供 6 项，影片入口为 `/bits-of-news/`。列表使用站点 AJAX 协议，详情首页普通 HTML、后续页 AJAX；完整路径快照见 `docs/knit-site-protocol-2026-08-28.md`。
- KnitGallery 图片详情与 4KHD/MissKon 一致：详情/沉浸区可见后才逐页加载；相邻两页作为预取预算，但只沿连续完成前缀逐页串行请求，失败页会阻断后续页与推荐直到显式重试成功；底部胶片条与最后一张后的原站推荐共用同一状态；推荐通过 Favorites adapter 传递并由 App 组装层路由。Knit JSON/HTML 纯解析经 `@concurrent nonisolated` 路径离开 MainActor；Cloudflare 验证等待按请求独立登记，取消请求会立即移除 waiter，最后一个 waiter 取消时同步关闭验证会话。HLS 视频只在 App 层独立 `AVPlayerView` 窗口播放，详情播放按钮与播放器画面的右键菜单均提供「保存视频为 MP4…」和「拷贝影片源 URL」；工具栏只在详情解析到真实 HLS 后启用保存，下载器逐段拉取受信任的 MPEG-TS VOD、AVFoundation 无损封装并校验 MP4 后原子安装。加密、直播、fMP4、byterange、独立音轨和 discontinuity 清单会明确拒绝，不静默生成残缺文件。
- Favorites 的详情契约由 adapter 注入而非来源类型分支：4KHD/MissKon/KnitGallery 复用原站分页、胶片条与推荐，Gallery 保留 WebKit fallback；KnitGallery 额外注入播放/复制影片源/MP4 保存动作；MissKon 通过来源无关外部动作保留 MediaFire 入口；Wallhaven 使用原图、完整 metadata、设为壁纸、同来源记录导航与应用内上传者路由。分页按来源真实容量（20/12/10/1）和连续完成前缀串行推进，失败页保留并支持状态区点击重试，不得越过缺口或提前显示推荐；初始占位窗口上限为 1,000，窗口外页面按需插入。
- Favorites 的 UI 选择以标准化 detail URL 为主身份，跨来源 raw ID 冲突不会串选；空筛选或删除最后一条记录会清空旧详情。持久化封面在列表、预取和详情首图使用前重新经过来源媒体门禁；保存消息只有一条观察链，旧记录回调由 generation 隔离。Gallery/MissKon 请求合并器在最后一个 waiter 取消时会取消底层任务，避免已关闭详情继续占用解析或 WebKit。
- Knit 视频保存的清单与分片遇到 403 或 `cf-mitigated: challenge` 时，整次任务最多共享一次正常 WebKit 验证并重试触发请求一次；重试仍执行 Cookie、媒体 host 和重定向门禁。HLS 清单先落到临时文件，确认不超过 5 MB 后才映射读取。播放器观察 `AVPlayerItem.status` 并在失败时显示一次原生提示。当前 `AVPlayer` 自行发起的 HLS 子请求不经过应用的 `OnlineSourcePolicy`，全链播放门禁仍需自定义资源加载器或本地代理。
- 视频保存不再使用占据前台的进度弹窗：工具栏保存菜单或「播放视频」按钮右键菜单都可启动 MP4 保存；用户选定目标后，`SingleFileDownloadSource` 作为 `.video` 任务进入与图集共用的 `DownloadStore` 串行队列。普通非模态下载窗口只保留标题栏中的单一标题，任务行在进度条下方显示已下载/总大小、整体百分比与当前速度，完成后以最终 MP4 或实际图集文件字节显示精确大小和平均速度；图集按单图、视频按 HLS 分片完成采样并平滑。活动或排队中的单文件目标路径会被队列预留，避免两个不同视频在首个文件尚未落盘时写入同一路径；任务终结或取消后释放。关闭窗口不终止任务，在线收藏使用同一右键菜单与队列。Knit 图片详情的胶片条上方不再显示分类或下载完成文字。
- 设置中的收藏 JSON 备份直接快照 `FavoritesStore`，因此包含 KnitGallery 的 `FavoriteRecord` 全字段；回归测试覆盖导出到新 Store 导入的无损往返。导入只接受当前四个来源的受信 HTTPS 详情 URL，并以稳定顺序、后项覆盖规则处理重复 `detailURL`，不会再由 `Dictionary(uniqueKeysWithValues:)` 触发崩溃。
- Inspector 仍由 App 层单一窗口服务六个模块，但已改为来源图标/标题固定头部与可滚动的动态分组网格；缺失行直接省略，来源链接和本地路径提供系统打开动作。窗口关闭或最小化后通过 generation 停止观察和 metadata 任务，重新打开不再覆盖用户保存的位置；无当前项目时菜单与工具栏信息命令禁用。
- Gallery 当前媒体跳转由 `OnlineRedirectGuard` 校验：Referer 缺失时按 original/current media URL 的唯一 allowlist 归属回退；`i0.wp.com` 只能代理明确列出的 Gallery 来源路径，不得扩成整个 `wp.com`/`googleusercontent.com`。
- Favorites 持久化由 `FavoritesStorageCoordinator` actor 串行拥有；本地目录持久化使用 security-scoped bookmark；本地缩略图位于 Caches。

## 状态机与 UI 契约

- 在线异步结果必须携带请求时 section/query/page 或完整 item snapshot，取消后回滚 cursor/bookkeeping，旧 token/generation 不得回写。
- Gallery latest 优先使用数值型 `query-3-page` 栏目分页，不能被全站 SEO `rel=next` 覆盖；仅在无显式栏目链接时合成下一页，并用重复页 identity 终止。MissKon 详情首页完成后最多预取相邻两页，此后只按接近尾部或显式导航推进，不可由 observer 自动拉完整图集。
- Gallery/MissKon/KnitGallery 在最后一张后继续导航才进入推荐页；向前导航回到最后一张。MissKon 固定 6 项按宽区 3×2、窄区 2×3 排列；KnitGallery 推荐数量跟随原站。推荐点击必须打开精确 detail URL。
- 工具栏、菜单和检查器均读取当前模块 snapshot/descriptor。没有当前项目时，保存、共享、适合窗口、胶片条和大图模式必须禁用。
- `⌘0` 唯一语义是“适合窗口”；`⌘1/2/3` 聚焦三栏，`⌘\` 切换详情栏；只接受精确修饰键组合。
- Inspector、Downloads、Preferences 是 AppDelegate 长期持有且 `isReleasedWhenClosed = false` 的辅助窗口；关闭后隐藏/复用，不重复创建。Downloads 是普通非模态窗口，Inspector 保持浮动工具面板但隐藏时停止后台观察。

## 已知边界与结构债务

- 顶部系统工具栏在部分三栏/详情栏状态下仍可能丢失 scroll-edge 半透明背景；鼠标悬停或窗口失焦后背景恢复。内容继续穿过系统工具栏下方是正确目标，不得用 safe-area 截断、自绘工具栏背景、hover 监听或全窗材质层伪装成修复。该问题本批不再改代码。
- `KnitContentViewController.swift`、`KnitVideoDownloadService.swift` 和 `KnitGalleryStore.swift` 已超过 UI 规范建议的约 300 行拆分阈值。当前功能和测试优先，本次发布前不做高风险临时重构；后续按 UI、传输/封装、状态机职责分别拆分。
- 当前 `AVPlayer` 自行发起的 HLS 变体清单和分片请求不经过应用的 `OnlineSourcePolicy`；入口 URL 已门禁，下载链为逐请求门禁。若播放也要求全链审计，需要自定义资源加载器或本地代理。
- 仍未建立指定 10k/50k 本地图库的 Instruments 基线；N-1 应用内真实 Sparkle 升级安装由用户自行验收。

## 缓存位置

- 通用详情页：`~/Library/Application Support/4KHD/DetailPageCache/pages.json`
- MissKon 列表：`~/Library/Application Support/4KHD/MissKon/feed-cache.json`
- MissKon 详情 metadata：`~/Library/Application Support/4KHD/MissKon/DetailMetadata/pages.json`
- Wallhaven 详情：`~/Library/Application Support/4KHD/Wallhaven/detail-cache.json`
- 本地缩略图：`~/Library/Caches/4KHD/LocalImageThumbnails/`
- 收藏：`~/Library/Application Support/4KHD/favorites.json` 与上一完整快照 `.bak`

## 下一步边界

1. 先阅读本文件和 `AGENTS.md`；历史审查清单只作为截至 1.8.8 的证据，不得覆盖当前代码事实。
2. 不要重做已关闭问题；新增改动须继续补对应回归测试并保持生产代码 0 SwiftUI。
3. 后续新增修改仍需明确授权再提交或推送；保留工作树中与任务无关的并行修改。

## 验证命令

```bash
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Release -destination 'platform=macOS' build
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' test
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
git diff --check
```
