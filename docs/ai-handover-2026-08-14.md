# 4KHD AI Handover — 2026-08-14

给下一个开发助手恢复上下文用。更细的架构规范看 `AGENTS.md`。

## 当前状态（已验证）

- Swift 6 Debug 构建通过，零代码警告；`4KHDTests` 全部通过（42 例）。
- 生产代码纯 AppKit，无 SwiftUI；模块间无直接 import。
- 应用实机启动验证通过：网格渲染、详情加载、双击缩放往返、切换图片均正常。
- 图集批量下载 + 下载管理器已实现（工具栏「保存」菜单、Window→Downloads 浮窗），引擎与调度逻辑有单元测试覆盖；菜单/浮窗交互尚未实机点击验证。
- 内容区滚动位置记忆：开关详情面板 / 进出大图导致网格列数变化时，瀑布流布局记录滚动锚点并恢复（`WorkspaceThumbnailWaterfallLayout` 的 pendingScrollAnchor 机制，覆盖 Gallery/MissKon/Wallhaven；LocalLibrary 自带恢复逻辑）。

## 本轮修复与优化摘要

**崩溃 / 卡死**
- Gallery 列表首行按上箭头 `rows[-1]` 越界崩溃（已夹取并加空数组 guard）。
- 详情图同 URL 重试被 `loadedURL` guard 挡住、失败占位永不清除（Gallery/MissKon/Wallhaven 三处 setImageURL guard 放宽为“URL 相同且已有图才跳过”；RemoteImageView 同款修复）。
- Gallery 切换板块不取消在途任务，`isRefreshingList` 永久卡 true（section.didSet 现取消列表/搜索任务并重置状态）。
- DetailImageResolver 旧导航的 didFinish/didFail 回调无代次校验，会把重试中的当前页误标失败（新增 `webLoadGeneration`）。

**布局**
- 瀑布流布局 `prepare()` 在 LayoutMetrics 不变时提前返回，宽高比更新的重排被吞（新增 `invalidateCachedFrames()`，三个网格容器改用）。
- `updateCachedFrames` 不回写 `columnHeights`，重排后懒生成卡片错位（已同步）。
- MissKon 分页 URL 未归一尾部斜杠（已与 MissKonDetailResolver 的 canonicalBase 逻辑对齐）。

**数据 / 缓存**
- LocalLibrary：目录不可读（外接磁盘断开）时刷新会误删根目录与排除项（现仅目录存在才删）；导入扫描期间删根会被重新插回；被取消的导入任务覆盖 `isScanning`；`allImages` 缓存在内容替换但数量不变时不失效。
- SiteListResolver latest 分页永不终止（页面有页码链接时按真实链接判断末页；无链接保持原 +1 行为）。
- MissKon 翻到末页后切回重拉第 1 页（`noMorePagesSections` 终态随 CacheSnapshot 持久化）。
- DetailPageImageCache.clear 异步化（磁盘删除离开主线程）；应用退出时 flush 落盘。
- DataCache.sweep 移到后台（原同步遍历阻塞启动与缓存上限调整）。
- Wallhaven 收藏反序列化 purity 写死 `.sfw`（现从 subtitle 反查，WallhavenPurity 标为 nonisolated）。

**图片管线**
- 在线图片解码加高度上限：`Resize(size: width × height×2, aspectFit)`，超长图不再解码失控；普通竖图不受影响。
- Gallery 详情加 4096 解码上限（与 MissKon/Wallhaven 一致），消除 8K 原图内存尖峰。
- 预取 destination 改为 `.diskCache`（原来只进内存，重启即失效）。
- 加载瞬时网络错误自动重试一次（仅 timeout/connectionLost/hostUnreachable 类；解码失败与取消不重试）。
- 网格缩略图按 `resolvedColumnWidth × backingScale` 动态解码（512–1536px），列数少的大卡片不再放大 512px 糊图。

**体验**
- 详情图加载完成 0.15s 淡入（缓存命中/保留旧图路径不 fade）；缩略图同款。
- 详情图双击放大 2x / 还原 fit（基类实现，四个详情视图共享）。
- 未选中图片时“上一张/下一张”菜单禁用（MissKon/Wallhaven）。
- 保存图片：先移废纸篓再复制（复制失败不丢原文件），拷贝在后台执行。
- 快速连按不同卡片上一张不再卡按压缩放态。
- MissKon/Wallhaven 列表单击行同步选中（详情面板与方向键跟随，与网格一致）。
- 侧边栏：本地根目录拖拽取消会回滚实时重排；折叠分组内的路由节点会先展开再选中。
- Wallhaven 列表 footer 状态就地刷新，不残留旧错误文案。
- Gallery 收藏分组表头展开/折叠改为单击手势（修复双击 toggle 两次抵消）；表头右键菜单快照回调防复用错位。
- 本地列表搜索词变化但结果集不变时也刷新行高亮。

## 图集批量下载（本轮新增）

- 引擎:`Shared/Services/Download/` — `AlbumDownloadOrchestrator.run`(nonisolated 纯逻辑,逐页串行 resolve + 页内 3 路并发,失败重试一次,取消提前返回);`AlbumDownloadSource` 由 Gallery/MissKon 各提供工厂(解析器默认 MainActor,闭包标 `@MainActor`);`DownloadStore`(@MainActor @Observable)严格串行调度任务,`imageFetcher` 属性是测试注入点(生产 nil)。
- 完整性保证:首页解析成功后以权威 pageURLs 整体替换 worklist 并从头扫描(入口页不是第 1 页也不漏不重);页解析失败自动重试一次;跨页重复图片按 URL 去重(分页边界常重复最后一张);同名图集并发下载经 `reservedFolderPaths` 分配独立目录。
- 工具栏:onlineSave 改为 NSMenuToolbarItem(保存当前图片 / 保存整个图集…),`canSaveAlbum` 只在 Gallery/MissKon 快照存在;Wallhaven 保持单张语义。
- 浮窗:`WorkspaceDownloadsWindowController`(utility 面板,关闭=隐藏 orderOut,任务继续);行状态 图标/标题/副标题/进度条(总数未知时不定态)/行尾按钮,右键菜单含「在 Finder 中显示」。
- 取消语义:已下载文件保留;running 取消经 `activeJob.cancel()` + `registry.cancelAll()`;全部失败 → failed + 删空目录;重启不持久化任务。
- Swift 6 注意:SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor 下,未标注结构体隐式 MainActor(成员 MainActor 隔离),不写显式 Sendable(编译器自动推断);引擎与 store 的边界靠 `await`/`Task { @MainActor }` 自动切换。

## 维护约束

**新增**
- 图片请求构造统一走 `RemoteImagePipeline.request`；`maxPixelSize` 是宽度上限语义，高度上限自动为 2 倍。
- 网格缩略图解码尺寸用 `thumbnailMaxPixelSize`（基于布局 `resolvedColumnWidth`），不要退回固定 512。
- 预取 destination 保持 `.diskCache`；`DataCache.sweep` 只能在后台队列调用。
- `WorkspaceThumbnailWaterfallLayout` 的宽高比更新必须用 `invalidateCachedFrames()`，`invalidateLayout()` 不会触发重排。

**继承自 7-28，仍然有效**
- 新增模块时同时接入 `WorkspaceToolbarContext` 的统一布局/列数命令。
- 不要把 URLCache 恢复为第二套在线图片磁盘缓存（磁盘层只有 Nuke DataCache）。
- 缓存写入不得在 MainActor 上执行，也不得绕过各 Store 的 `clearCache()`。
- 普通在线列表零匹配不得更新缓存时间；搜索空结果必须由页面中的明确空状态标记确认。
- 收藏 UI 状态只能在持久化成功后更新，失败必须保留原状态并提示用户。
- 需要扩展网络兼容性时，先确认具体 HTTPS 失败证据；不要恢复宽泛 ATS 例外。

**生命周期**
- `WorkspaceColumnHostController` 的 vibrancy 包装视图一次性创建并复用（原来每次切换内容控制器累积一个、从不移除）。
- `WorkspaceCoalescingQueue` deinit 时 invalidate 计时器。
- 偏好设置导出与工具栏 toggleFavorite 的 Task 弱捕获 self。
- 实机验证：80 次模块切换内存稳定（首轮峰值后回落到基线），无持续泄漏。

**回归测试**
- Gallery latest 分页：真实页码链接优先、末页终止、无链接回退 +1（3 例）。
- MissKon 分页 URL 尾斜杠归一（1 例）。
- Wallhaven 收藏纯度从 subtitle 反查 + SFW 回退（2 例）。
- 图集下载：编排器并发上限/重试/页失败继续/取消/目录失败/worklist 替换（6 例）、错页开头不重不漏/跨页去重/页解析重试（3 例）、文件名规整与冲突序号（3 例）、DownloadStore 串行调度/去重/取消/删空目录/清理（6 例）、同名图集独立目录（1 例）。
- 当前共 42 个测试全部通过。

## 已知剩余风险

- `FavoritesStore` 的 toggle/import/removeAll 跨 await 读-改-写，极端并发下可能丢更新（低概率，修复需引入二次 persist）。
- `HTMLRequestCoalescer` 调用者取消后底层 task 仍执行，同 URL 可能重复抓取一次（Gallery/MissKon 同构，影响小）。
- Gallery latest 分页的末页判断依赖真实页面含页码链接；无链接的旧页面保持原 +1 行为，建议实机翻到末页确认一次。
- 加载重试不传播原 ImageTask 的取消（重试已发起时用户取消不影响重试任务，结果会被 loadedURL guard 丢弃）。
- 图集下载：工具栏菜单、目录选择面板、下载浮窗的行交互尚未实机点击验证（引擎/调度逻辑已测试覆盖）；取消竞态窗口（任务恰好完成时点取消）可能落为 completed 而非 cancelled。
- 滚动锚点恢复为异步（下一个 runloop）执行，极端快速连续开合面板时可能有一次轻微位置偏差；列表模式行高固定不受影响。
- MissKon 详情 `prepare` 对同 ID item 直接跳过，列表刷新替换同 ID item 对象时 detail 持有旧快照（影响小，未修）。
- 测试宿主运行在沙盒内（容器 `com.songziqiang.-KHD`），调试日志写到 `FileManager.default.temporaryDirectory` 时在容器 tmp 下，不在宿主 /tmp。

## 两轮审查已修复（第二轮）

- 下载引擎 worklist 替换后的失败页不再被成功页的重新扫描反复解析（restartScan 在失败分支消费）。
- Gallery 详情 pending 跳转：stepImage 无更多页时回退末位不悬挂 pending；用户主动选中已加载位置时清 pending，防止在途页到位把选中强制拉走。
- 胶片条在占位槽被解析结果替换（knownURL 变化）时刷新可见槽缩略图。
- 滚动锚点在内容替换（刷新/搜索/切换）时由宿主显式清除，防止旧锚点应用到数量相同的新内容。
- 设置面板导入/清空收藏的 Task 改弱捕获 self；侧边栏默认展开 ID 修正为 `group:4KHD`。

## 验证命令

```bash
# 全量构建
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build

# 单元测试
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' test

# SwiftUI 生产代码检查
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'

# 补丁卫生
git diff --check
```
