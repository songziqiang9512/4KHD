# 4KHD AI Handover — 2026-08-23

本文件只保留当前可执行事实；详细问题、证据、逐项修复结果和外部验收边界见 `docs/optimization-remediation-2026-08-23.md`。

## 当前状态

- 当前分支 `main`；本文件对应 1.8.7 发布候选，完整改动和逐项结果见修复清单。
- 源码版本 1.8.7（build 187），最低系统 macOS 26.4；生产代码纯 AppKit、0 SwiftUI。
- 最终 Debug/Release 构建通过；全量 XCTest 82/82 通过；生产代码 SwiftUI 禁用扫描与 `git diff --check` 通过。
- 发布代码门禁已补齐；GitHub `release` environment 已限制为 `main` 并要求仓库所有者审批，4KHD 专属 Sparkle EdDSA 密钥已配置为 GitHub Secret。最终签名/公证 DMG 与 N-1 更新安装仍以实际发布环境为准。

## 当前架构事实

- `WorkspaceModuleRegistry` 的 descriptor 同时拥有模块 controller factory、route/bootstrap 和 `presentation` 工具栏能力；不要在 ToolbarHost 恢复 moduleID 条件链。
- Favorites 只依赖 `FavoriteRecord`、`FavoriteSource` 和 `FavoriteSourceAdapter` 契约。Gallery/MissKon/Wallhaven adapter 在 `WorkspaceAppAssembly` 注册；Favorites 内不得直接引用其他业务模块的 bridge/resolver/model。
- `DetailPageImageCache` 只缓存跨站通用图片页；MissKon 专属 MediaFire metadata 归 `MissKonDetailMetadataCache`。
- 在线请求统一经过 `OnlineSourcePolicy` 与各模块 request factory：仅 HTTPS、exact/subdomain allowlist，并验证最终响应 host；不使用 `host.contains(...)`。
- Gallery 当前媒体跳转由 `OnlineRedirectGuard` 校验：Referer 缺失时按 original/current media URL 的唯一 allowlist 归属回退；`i0.wp.com` 只能代理明确列出的 Gallery 来源路径，不得扩成整个 `wp.com`/`googleusercontent.com`。
- Favorites 持久化由 `FavoritesStorageCoordinator` actor 串行拥有；本地目录持久化使用 security-scoped bookmark；本地缩略图位于 Caches。

## 状态机与 UI 契约

- 在线异步结果必须携带请求时 section/query/page 或完整 item snapshot，取消后回滚 cursor/bookkeeping，旧 token/generation 不得回写。
- Gallery latest 优先使用数值型 `query-3-page` 栏目分页，不能被全站 SEO `rel=next` 覆盖；仅在无显式栏目链接时合成下一页，并用重复页 identity 终止。MissKon 详情只按接近尾部或显式导航推进，不可 observer 自动拉完整图集。
- 工具栏、菜单和检查器均读取当前模块 snapshot/descriptor。没有当前项目时，保存、共享、适合窗口、胶片条和大图模式必须禁用。
- `⌘0` 唯一语义是“适合窗口”；`⌘1/2/3` 聚焦三栏，`⌘\` 切换详情栏；只接受精确修饰键组合。
- Inspector、Downloads、Preferences 是 AppDelegate 长期持有且 `isReleasedWhenClosed = false` 的辅助窗口；关闭后隐藏/复用，不重复创建。

## 缓存位置

- 通用详情页：`~/Library/Application Support/4KHD/DetailPageCache/pages.json`
- MissKon 列表：`~/Library/Application Support/4KHD/MissKon/feed-cache.json`
- MissKon 详情 metadata：`~/Library/Application Support/4KHD/MissKon/DetailMetadata/pages.json`
- Wallhaven 详情：`~/Library/Application Support/4KHD/Wallhaven/detail-cache.json`
- 本地缩略图：`~/Library/Caches/4KHD/LocalImageThumbnails/`
- 收藏：`~/Library/Application Support/4KHD/favorites.json` 与上一完整快照 `.bak`

## 下一步边界

1. 先阅读修复清单，并以 `build-1.8.7` 发布流水线和 GitHub release 的最终产物作为签名、公证、Sparkle feed 等外部门禁的权威证据。
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
