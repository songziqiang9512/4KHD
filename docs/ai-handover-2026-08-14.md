# 4KHD AI Handover — 2026-08-14

给下一个开发助手恢复上下文用。更细的架构规范看 `AGENTS.md`。

## 当前状态（已验证）

- Swift 6 Debug 构建通过，零代码警告；`4KHDTests` 全部通过。
- 生产代码纯 AppKit，无 SwiftUI；模块间无直接 import。
- 应用实机启动验证通过：网格渲染、详情加载、双击缩放往返、切换图片均正常。

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

## 已知剩余风险

- `FavoritesStore` 的 toggle/import/removeAll 跨 await 读-改-写，极端并发下可能丢更新（低概率，修复需引入二次 persist）。
- `HTMLRequestCoalescer` 调用者取消后底层 task 仍执行，同 URL 可能重复抓取一次（Gallery/MissKon 同构，影响小）。
- Gallery latest 分页的末页判断依赖真实页面含页码链接；无链接的旧页面保持原 +1 行为，建议实机翻到末页确认一次。
- 加载重试不传播原 ImageTask 的取消（重试已发起时用户取消不影响重试任务，结果会被 loadedURL guard 丢弃）。

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
