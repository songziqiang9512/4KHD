# 4KHD AI Handover — 2026-09-01

本文件只保留当前可执行事实。截至 1.8.9 的 KnitGallery 交接见 `docs/ai-handover-2026-08-28.md`；每日大赛站点协议见 `docs/mrds-site-protocol-2026-08-31.md`。

## 当前状态

- 当前分支 `main`，本批目标版本 1.9.0（build 190），最低系统 macOS 26.4；生产代码纯 AppKit、0 SwiftUI。
- 本批新增独立模块 MrdsGallery（侧边栏「每日大赛」）、Favorites/下载/Inspector 五来源接入，以及 Knit/Mrds 共用的 AES-128 MPEG-TS VOD 保存。网格卡片标题始终可见；分类切换走内存列表缓存且封面不先清空。
- 最终全量 XCTest 共 163 项：162 通过、1 项真实联网 HLS 保存测试按默认门禁跳过、0 失败；Debug 与 Release 构建通过。生产代码 SwiftUI 禁用扫描、workflow/YAML 静态校验与 `git diff --check` 通过。
- 1.9.0 采用现有受保护 `Build Prerelease` 流程：版本先提交到 `main`，随后由 GitHub Actions 测试、Developer ID 签名、Apple 公证、DMG/staple、Sparkle EdDSA appcast 和不可变 prerelease 完成。按本轮用户要求，正确推送并触发后即移交用户观察，不等待远端任务结束，也不重复下载公开产物。

## 当前架构事实

- `WorkspaceModuleRegistry` 的 descriptor 同时拥有模块 controller factory、route/bootstrap 和 `presentation` 工具栏能力；不要在 ToolbarHost 恢复 moduleID 条件链。
- Favorites 只依赖 `FavoriteRecord`、`FavoriteSource` 和 `FavoriteSourceAdapter` 契约。Gallery/MissKon/Wallhaven/KnitGallery/MrdsGallery adapter 在 `WorkspaceAppAssembly` 注册；Favorites 内不得直接引用其他业务模块的 bridge/resolver/model。
- 4KHD/MissKon/KnitGallery/MrdsGallery 推荐图集统一使用 `OnlineGalleryRecommendation`、`WorkspaceDetailContentMode` 和 `DetailRecommendationsView`；Favorites 只从 adapter 接收推荐数据，跨模块打开由 App 组装层路由。
- 在线请求统一经过 `OnlineSourcePolicy` 与各模块 request factory：仅 HTTPS、exact/subdomain 或 exact-host allowlist；不使用 `host.contains(...)`。
- MrdsGallery 侧边栏为最近更新 + 原站 20 个分类；列表为普通 HTML 分页（无 AJAX JSON）。详情单页 `/archives/{id}/`，图片在 `data-xkrkllgl`；占位图 `/usr/plugins/tbxw/zw.png` 不是原图。完整路径快照见 `docs/mrds-site-protocol-2026-08-31.md`。
- `pic.sbhioa.cn` 正文是 AES-128-CBC 密文（站点前端同一密钥/IV）。列表、详情、胶片条、保存和整图集下载都必须先经 `MrdsImageDecryptor` / `RemoteImageResponseMapper` 再解码或落盘；已是 JPEG/GIF/PNG/WebP 魔数的字节原样使用。
- Mrds HLS 媒体 host 会在 `ts.syjiaotong.mobi` / `tx.doudou520.online` / `ts.zhixunkeji.xyz` 间轮换；密钥 URI 不在 allowlist 时应抛 `OnlineSourcePolicy.PolicyError.rejectedURL`，不要吞成 `.invalidPlaylist`。
- Knit/Mrds 视频保存共用 `KnitVideoDownloadService`：`METHOD=AES-128` 先下载 16 字节密钥并按 KEY 行 IV 解密每个 TS，再无损封装。SAMPLE-AES、无 ENDLIST、独立音轨等仍拒绝。Knit 遇 403/`cf-mitigated: challenge` 最多共享一次 WebKit 验证；Mrds 没有 Cloudflare，403 直接失败。
- 视频播放复用 App 层 `KnitVideoPlayerWindowController`；Mrds 传入 `source: .mrds`。当前 `AVPlayer` 自行发起的 HLS 子请求不经过 `OnlineSourcePolicy`。
- Favorites 分页容量：4KHD 20、MissKon 12、KnitGallery 10、Wallhaven 1、MrdsGallery 单页容量=记录图片数。选择身份以标准化 `detailURL` 为主键。
- 设置中的收藏 JSON 备份直接快照 `FavoritesStore`，因此包含 KnitGallery 与 MrdsGallery 的 `FavoriteRecord` 全字段；导入只接受通过对应 `OnlineSourcePolicy` HTTPS 门禁的来源详情 URL。

## 已知边界与结构债务

- 顶部系统工具栏在部分三栏/详情栏状态下仍可能丢失 scroll-edge 半透明背景。内容继续穿过系统工具栏下方是正确目标；不得用 safe-area 截断、自绘工具栏背景、hover 监听或全窗材质层伪装成修复。
- `KnitVideoDownloadService.swift` 已超过 UI 规范建议的约 300 行拆分阈值。AES-128 保存加在既有传输路径上，本次发布前不做高风险临时重构。
- 当前 `AVPlayer` 自行发起的 HLS 变体清单和分片请求不经过应用的 `OnlineSourcePolicy`；入口 URL 已门禁，下载链为逐请求门禁。
- 仍未建立指定 10k/50k 本地图库的 Instruments 基线；N-1 应用内真实 Sparkle 升级安装由用户自行验收。

## 缓存位置

- 通用详情页：`~/Library/Application Support/4KHD/DetailPageCache/pages.json`
- MissKon 列表：`~/Library/Application Support/4KHD/MissKon/feed-cache.json`
- MissKon 详情 metadata：`~/Library/Application Support/4KHD/MissKon/DetailMetadata/pages.json`
- Wallhaven 详情：`~/Library/Application Support/4KHD/Wallhaven/detail-cache.json`
- 本地缩略图：`~/Library/Caches/4KHD/LocalImageThumbnails/`
- 收藏：`~/Library/Application Support/4KHD/favorites.json` 与上一完整快照 `.bak`

## 下一步边界

1. 先阅读本文件和 `AGENTS.md`；历史交接不得覆盖当前代码事实。
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
