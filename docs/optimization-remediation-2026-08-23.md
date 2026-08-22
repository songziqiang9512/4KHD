# 4KHD 全面审查问题修复清单

更新日期：2026-08-23
状态：代码修复与 UI 结构审查完成；外部发布验收和真实大图库性能基线待执行
范围：发布链、数据安全、沙盒权限、图片与缓存、在线模块状态机、Shell/UI 行为、模块边界、性能、构建质量与最终 UI 结构审查。

本文件是本轮修复的唯一进度账本。源码和可复现验证优先于本文件；每个条目只有在对应测试/构建/产物检查通过并填写“结果”后才能标记完成。

## 状态约定

- `[ ]` 待处理
- `[~]` 处理中
- `[x]` 已完成并验证
- `[!]` 已确认但需要外部凭据、签名环境或人工 UI 验证
- `[-]` 复核后排除，必须记录排除证据

## 当前基线

- 分支：`main`，开始执行时与 `origin/main` 一致，工作树干净。
- 生产 UI：AppKit，SwiftUI 禁用项扫描无命中。
- 自动化：Debug XCTest 50/50 通过；arm64 Release 构建通过。
- 已知构建债务：多个 AppKit 通知回调存在 MainActor 隔离 warning。
- 发布产物抽查：当前 `build-1.8.5` DMG 有 Developer ID 签名和公证票据，但主 App 无 entitlements。
- 提交策略：本轮不自动提交；只有用户明确授权后才提交。

## 执行规则

1. 每批先补能够稳定复现问题的测试或脚本门禁，再修实现。
2. 修复在线模块时校验请求 identity、section/query/page 快照、取消和 stale-write。
3. 修复 Shell 集成时搜索所有 `WorkspaceModuleID` switch surface。
4. 生产代码继续保持 0 SwiftUI；优先使用 AppKit 系统能力。
5. 不以单次编译成功替代行为测试；发布问题必须检查最终 DMG，而不是 DerivedData 中间产物。
6. 所有功能与结构问题关闭后，才开始“UI 结构全面系统审查”。

## A. 发布链与最终产物

- [x] **REL-001 发布重签丢失 entitlements**
  证据：`script/sign_release_app.sh` 对主可执行文件和 App 再次 `codesign --force`，未传入或保留 entitlements；当前 1.8.5 DMG 实测无 entitlements。
  修复目标：优先使用 archive/export；若保留脚本，按组件类型正确签名并保证主 App 权限完整。
  验收：挂载最终 DMG 后逐项断言 sandbox、user-selected、Downloads、Pictures、network entitlement。
  结果：发布工作流已删除二次通签步骤和 `sign_release_app.sh`；新增 `verify_release_app.sh`。本地签名 Release 样本已验证主 App 保留 sandbox、Pictures、Downloads、user-selected、bookmark、network 与 Sparkle mach-lookup 权限。

- [x] **REL-002 任意分支 push 都可写 release 与自动更新 feed**
  证据：`build-prerelease.yml` 监听 `branches: "**"`，并持有 `contents: write`。
  修复目标：拆分只读 CI 与受保护发布工作流；发布仅允许受保护 tag 或人工批准环境。
  验收：普通分支/PR 不可访问签名秘密、不可创建 release、不可覆盖 appcast。
  结果：仓库代码已拆成只读 `ci.yml` 与仅支持 `workflow_dispatch`、main、显式确认、`release` environment 的发布工作流；GitHub `release` environment 已启用仓库所有者审批，并以自定义部署分支策略只允许 `main`。

- [x] **REL-003 版本在 CI 临时递增，tag 无法复现产物**
  证据：`build-1.8.5` 指向的源码仍为 1.8.4/184，CI 工作树临时改成 1.8.5/185 后打包。
  修复目标：版本必须提交到源码或严格由不可变 tag 派生；同一 commit 不得对应多个不同版本 tag。
  验收：从 tag 干净 checkout 构建出的版本与 release/appcast 完全一致。
  结果：发布工作流不再调用 `update_version.sh --next`；输入版本必须等于已提交的 Release build settings，既有 tag/release 均拒绝覆盖。

- [x] **REL-004 发布工作流没有 XCTest 门禁**
  修复目标：签名和发布前执行测试；任何失败不得进入签名、公证和 feed 发布。
  验收：工作流结构测试或脚本检查确认依赖链。
  结果：签名构建前新增 Debug XCTest；普通 CI 同时运行测试和 unsigned Release 编译。

- [x] **REL-005 Sparkle 更新归档没有 EdDSA 签名**
  证据：Info.plist 无 `SUPublicEDKey`，appcast 无 `sparkle:edSignature`，预解压验证关闭。
  修复目标：配置公钥、CI 私钥和 `SUVerifyUpdateBeforeExtraction`；私钥只存在于受保护发布环境。
  验收：生成 appcast 含 edSignature，错误签名包被拒绝。
  结果：Info.plist 已接入构建期 `SUPublicEDKey` 并启用预解压验证；工作流要求受保护的公私钥 secret，以 stdin 传给 `generate_appcast --ed-key-file -` 并断言 `sparkle:edSignature`。已用锁定版本的 Sparkle 官方工具生成 4KHD 专属密钥并配置为 GitHub Secret；私钥未写入仓库，最终签名断言由 1.8.6 发布流程执行。

- [!] **REL-006 沙盒版 Sparkle installer 配置不完整**
  证据：缺少 `SUEnableInstallerLauncherService` 及 `-spks/-spki` mach-lookup 权限。
  修复目标：按 Sparkle sandboxing 契约配置；验证从 N-1 公证版本升级。
  验收：沙盒内真实更新安装、重启和版本切换成功。
  结果：已加入 Installer Launcher 开关和 `-spks/-spki` mach-lookup 权限，本地最终 App 权限门禁通过；N-1 安装仍需真实签名发布包验证。

- [x] **REL-007 最终发布验收未检查权限、版本和 dSYM**
  修复目标：扩展 `verify_packaged_dmg.sh`，验证 entitlements、Info.plist 版本/架构、Sparkle 配置；上传匹配 dSYM。
  验收：门禁能稳定拒绝缺权限、错版本和缺 dSYM 的包。
  结果：`verify_packaged_dmg.sh` 现在调用严格 App 门禁；发布构建要求 dSYM 并压缩上传，appcast 与 notary 完整日志也进入 artifact。

- [x] **REL-008 发布工具供应链固定不足**
  证据：Actions 使用浮动大版本标签；Sparkle tarball 以硬编码 URL 下载但不校验 SHA-256。
  修复目标：关键 Actions pin 到 commit；下载工具校验固定哈希或复用已解析依赖。
  验收：脚本检查不存在未验证的发布期可执行下载。
  结果：checkout/upload-artifact 已 pin 到 commit；Sparkle 2.9.4 发布工具固定 SHA-256 并在解压前校验。

## B. 用户数据与持久权限

- [x] **DATA-001 保存到源文件会先把源文件移入废纸篓**
  修复目标：用 standardized/resolved URL 与 file resource identifier 判断同一文件；同文件直接成功，普通覆盖使用临时文件和原子替换。
  验收：same-file、symlink-to-same-file、普通覆盖、复制失败测试均不提前破坏源文件。
  结果：新增 `LocalImageSaveService`，同文件直接成功，普通覆盖先生成完整临时副本再原子替换；same-file、symlink 和覆盖测试通过。

- [x] **DATA-002 下载失败可删除用户已有空目录**
  修复目标：记录目标目录所有权；只删除本任务实际创建的目录，或永不复用既有空目录。
  验收：预建空目录 + 全失败后目录仍存在；任务新建空目录才允许清理。
  结果：下载分配器不再复用任何既有目录；失败任务不再删除目录。组合回归测试确认用户预建目录保持存在。

- [x] **DATA-003 本地图库只保存路径，没有 security-scoped bookmark**
  修复目标：保存 app-scope bookmark，处理 stale、离线、重授权和旧路径迁移；访问生命周期成对 start/stop。
  验收：模拟重建 Store 后仍能访问授权目录；移除 root 后释放访问。
  结果：新增 v3 bookmark 记录、旧路径迁移、stale 刷新和 Store 生命周期内的 start/stop；测试已覆盖导入、持久化、销毁后恢复和图片重新扫描。

- [x] **DATA-004 FavoritesStore 跨 await 读改写会丢并发更新**
  修复目标：由单一 actor/事务队列拥有读改写、原子持久化和发布顺序；toggle/import/removeAll/reload 同路。
  验收：门控并发测试确认内存与主文件包含全部成功操作，备份始终是可解码的上一份完整快照。
  结果：新增 `FavoritesStorageCoordinator` actor，toggle/import/removeAll/reload 共享一个权威快照和串行事务；并发双 toggle 测试确认无丢更新。

- [x] **DATA-005 收藏主文件与备份写入缺少统一事务边界**
  修复目标：临时文件写入、主文件替换、备份更新采用明确顺序；失败不得发布新内存状态。
  验收：在各阶段注入失败后可从主文件或备份恢复到完整快照。
  结果：只有可解码主文件才进入原子 backup，backup 成功后才原子替换主文件；写入失败不更新 actor 或 UI。既有写入失败与损坏恢复测试继续通过。

- [x] **DATA-006 下载远程文件名未统一规整和长度限制**
  修复目标：规整 basename、限制长度、限制扩展名并保持碰撞分配稳定。
  验收：非法字符、超长 Unicode、空 basename、危险扩展名测试通过。
  结果：basename 规整并限制 120 字符，扩展名限制为图片 allowlist，未知扩展回退 jpg；新增测试通过。

## C. 图片、缓存与本地扫描

- [x] **IMG-001 可复用缩略图 URL 改变时保留旧 bitmap**
  修复目标：普通 cell 在 identity 变化时清图；需要 last-ready 的详情路径使用显式模式。
  验收：A→B 未命中、B 失败、乱序回调、取消复用均不显示 A。
  结果：`RemoteImageView` 在 URL identity 变化和取消复用时立即清除 bitmap；last-ready 只保留为显式属性。A→B 未命中回归测试通过，旧请求回调仍由 URL guard 拒绝。

- [x] **IMG-002 首次瞬时失败会提前写负缓存，重试成功不清除**
  修复目标：只有终态失败才记负缓存，任何成功都清除；按 request identity 管理。
  验收：重试成功后同 URL 可立即复用。
  结果：首次可重试错误不再写负缓存；只有第二次终态失败写入，首次或重试成功都会删除 URL 的失败记录。

- [x] **IMG-003 延迟重试不属于原始可取消任务**
  修复目标：首次请求、退避和重试封装为一个可取消 handle；clear/cell reuse 可完整取消。
  验收：退避期间取消不再发请求，清缓存后重试不能重新填充缓存。
  结果：新增 `RemoteImageLoadTask`，统一持有首次 Nuke task、退避 work item 与重试 task；cell reuse 和 cache generation 失效均可完整取消。退避取消回归测试通过。

- [x] **IMG-004 清缓存提前报告完成且 live/disk 状态不一致**
  修复目标：异步 CacheClearCoordinator 等待磁盘删除，提升 generation，取消任务并统一重建当前模式。
  验收：完成回调后磁盘为空；MissKon/Wallhaven 下一页不会替换掉此前列表。
  结果：远程缓存清理改为 async 等待 DataCache 删除，先提升 generation 并取消全部图片任务；MissKon/Wallhaven 同步清空 live cursor/selection/detail 状态，磁盘删除完成后按当前模式刷新，旧任务 token 无法回写。

- [x] **IMG-005 本地缩略图首次写盘使用 replace 导致目标不存在时失败**
  修复目标：存在时 replace，不存在时 move；错误可观测且不留临时文件。
  验收：首写存在、二次磁盘命中、覆盖与失败清理测试通过。
  结果：目标不存在时 move 临时文件，存在时才 replace，并始终清理临时文件。测试在清除内存、删除源图后仍从首次磁盘写入命中。

- [x] **IMG-006 本地缩略图缓存放在 Application Support**
  修复目标：迁入 Caches，兼容清理旧目录，不把可重建数据当持久用户数据。
  验收：新缓存路径、旧缓存迁移/清理和偏好设置清缓存测试通过。
  结果：新路径迁至 `Library/Caches/4KHD/LocalImageThumbnails`；首次访问尝试移动旧目录，清缓存同时删除新旧精确目录。路径与磁盘命中测试通过。

- [x] **IMG-007 磁盘 prune 缺少 single-flight/时间节流**
  修复目标：避免多个全目录扫描和排序重叠；按时间/容量阈值触发。
  验收：并发压力测试中最多一个 prune，频率受限。
  结果：actor 内新增唯一 prune task/id 和 5 分钟最短间隔；clear 会取消并等待 prune，遍历删除循环响应取消，不再重叠全目录排序。

- [x] **LOCAL-001 detached 扫描不能被外层取消**
  修复目标：结构化扫描或显式 worker handle；取消后停止目录访问并不回写旧结果。
  验收：慢扫描取消测试的访问计数立即停止。
  结果：单根扫描 worker 由 `withTaskCancellationHandler` 显式向 detached worker 传播取消；多根扫描继续使用结构化 task group，所有递归层检查取消且旧结果不回写。

- [x] **LOCAL-002 扫描未明确防 symlink 环和 package 展开**
  修复目标：按 resource identifier 去环，跳过 symlink/package，处理离线根。
  验收：symlink 环、照片库 package、权限错误测试通过。
  结果：扫描记录解析后的目录 identity，跳过 symbolic link/package 并启用 `skipsPackageDescendants`；包含自环 symlink 和 `.photoslibrary` 的回归测试仅发现根目录真实图片。

- [x] **LOCAL-003 全局像素尺寸缓存无容量与 root 清理策略**
  修复目标：容量限制/LRU；删除根时移除对应项。
  验收：大量图片压力测试中缓存有硬上限。
  结果：像素缓存改为带访问序的有界 LRU（默认 20,000，超限缩到 90%）；移除图库根时按精确路径前缀清理。小容量压力回归测试通过。

## D. 在线模块与 URL 安全

- [x] **WH-001 上传者 HTML fallback 绕过 purity 和 uploader 身份校验**
  修复目标：API 与 fallback 统一执行精确 purity 谓词和 uploader 身份校验。
  验收：混合 SFW/Sketchy/NSFW 与错误 uploader 注入测试通过。
  结果：API 与 HTML fallback 都进入同一精确 purity 过滤；上传者请求在建 Task 前快照 username/purity/key，回写前再次验证请求身份。混合 purity 与错误 uploader 定向测试通过。

- [x] **WH-002 purity 收紧后旧详情和旧解析任务未同步撤销**
  修复目标：立即清 selection/resolved detail，取消详情任务并阻止旧 generation 回写。
  验收：NSFW→SFW 且新请求失败时不再显示旧内容。
  结果：purity/section/query 切换统一撤销详情解析、清理 selection/resolved snapshot 和请求 token；旧 generation 无法恢复已被新门禁拒绝的详情。

- [x] **WH-003 Inspector 不观察异步解析后的 effectiveSelectedWallpaper**
  修复目标：读取并观察完整详情快照；旧解析不得污染新选择。
  验收：Inspector 打开后详情异步完成会更新字段。
  结果：Inspector 读取并观察 `effectiveSelectedWallpaper` 与解析状态，且 Wallhaven same-ID 新快照会更新当前详情；实机打开 Inspector 后字段随解析结果刷新。

- [x] **GAL-001 关闭 Gallery 详情取消请求但不回滚 cursor/requested 状态**
  修复目标：取消时原子释放 bookkeeping 或允许任务完成进入缓存。
  验收：取消第 2 页后重开必须先请求第 2 页，不能跳第 3 页。
  结果：取消页面请求会释放 requested/prefetch bookkeeping 并把 cursor 回滚到未完成页；定向状态机测试确认重开后仍请求原第 2 页。

- [x] **GAL-002 启动刷新被搜索取消后，清搜索可留下永久空列表**
  修复目标：用明确 load state 替代 attempted one-shot；取消回 idle，清搜索按需恢复请求。
  验收：挂起首次刷新→搜索→清搜索后基础栏目自动恢复。
  结果：首次加载改为可恢复 load state；搜索取消启动刷新时回到 idle，清空搜索会重启当前栏目加载。取消恢复测试通过。

- [x] **GAL-003 失败详情页在同一生命周期被永久跳过**
  修复目标：区分终态与可重试失败；用户重试或重开时允许重新请求并保留错误可见性。
  验收：瞬时失败页重试成功后补回正确顺序。
  结果：详情页失败保留精确 pageURL identity，用户 footer/详情重试只重试原失败页；成功后按原序合并且清理失败状态。定向测试通过。

- [x] **MK-001 详情 observer 会把渐进加载推进成全图集自动解析**
  修复目标：初始预算和推进下一页拆为不同 API；只有接近尾部/显式导航推进。
  验收：8 页图集静置只请求前 1–3 页。
  结果：初始解析预算与翻页推进拆开；prepare/resolve 只加载首页并预取最多两页，只有接近尾部或显式导航才继续。静置预算测试通过。

- [x] **MK-002 刷新保留旧尾页却把 cursor 退回 page 2**
  修复目标：页桶化或刷新时重建；内容尾部和最高连续游标一致。
  验收：加载三页后刷新，下一请求只能是 page 4 或明确从 page 1 重建。
  结果：刷新明确从首页重建详情页桶、slot 和 cursor，不再把旧尾页与新游标拼接；刷新后连续页推进测试通过。

- [x] **MK-003 same-ID 新快照不传播到详情**
  修复目标：同 ID 内容版本变化也发布选择/重建详情；Wallhaven 同构路径一并处理。
  验收：pageURLs/imageCount/详情字段变化后详情同步更新。
  结果：Gallery/MissKon/Wallhaven/Favorites 的详情任务 guard 从仅 ID 改为完整 item/record snapshot；same-ID 内容变化会重建或更新当前详情，测试覆盖 MissKon 与 Wallhaven 路径。

- [x] **ONLINE-001 detail identity 只比较 path，忽略 scheme/host/port**
  修复目标：canonical key 包含 exact host、scheme/effective port；分页剥离按站点 schema。
  验收：跨 host 同 path、数字详情 ID、合法分页与端口组合测试通过。
  结果：详情 identity 统一包含 HTTPS scheme、规范化 host、effective port 和站点定义的分页基路径；跨 host 同 path 不再相等，组合回归测试通过。

- [x] **ONLINE-002 HTML/收藏封面/重定向没有统一 OnlineSourcePolicy**
  修复目标：统一 HTTPS、exact/subdomain allowlist、相对 URL、媒体 host 和最终响应 host；跨源重定向拒绝或剥离密钥。
  验收：evil host、HTTP、localhost、可信源→不可信源重定向全部拒绝。
  结果：新增 `OnlineSourcePolicy` 和三站 request factory，统一 HTTPS、exact/subdomain allowlist、媒体 host、相对 URL 与最终响应 URL 校验；恶意 host、HTTP/localhost 和跨源重定向测试通过。

- [x] **ONLINE-003 footer 重试没有失败操作 identity**
  修复目标：列表首刷、load-more、搜索页、详情页分别重试原失败请求，不能统一退回 page 1。
  验收：各错误类型保持已有分页内容并重试正确页。
  结果：三个在线模块记录首刷/搜索/load-more/详情的精确失败操作；footer 重试不再统一退回 page 1。既有内容保留和原页重试测试通过。

- [x] **ONLINE-004 Gallery latest 无页码链接时缺少可靠终态**
  修复目标：基于明确页面终态/重复页指纹停止，避免无限合成 `currentPage + 1`。
  验收：无页码末页 fixture 能终止，正常中间页继续。
  结果：Gallery latest 为无显式分页链接的页面计算 item identity 指纹；重复页终止，唯一新页继续合成下一页。注入 resolver 的两条状态机测试通过。

- [x] **ONLINE-005 4KHD 新图集媒体重定向被安全守卫误拒绝**
  证据：新图集列表能刷新出 `Kiyo - Usada Pekora`，但缩略图和详情图均失败；统一日志显示媒体请求收到 302 后以 `NSURLErrorDomain -999` 结束。精确追踪确认当前链路包含 `img.4khd.com → i0.wp.com/yt4.googleusercontent.com/...`，详情源还可能落到 `yt4.googleusercontent.com`。URLSession/Nuke 的 `originalRequest` 也不保证保留自定义 Referer。
  修复目标：按原媒体 URL 的唯一 source allowlist 回退识别模块，只允许 Gallery 当前精确 CDN 主机与 `i0.wp.com` 下的精确来源路径，不放开整个 `googleusercontent.com` 或 `wp.com`。
  验收：恶意 lookalike、无关 WordPress 代理路径和相邻 Google CDN 继续拒绝；真实最新图集缩略图与 24 张详情图可加载。
  结果：`OnlineRedirectGuard` 改为 Referer 优先、original/current media URL 唯一来源回退；Gallery media allowlist 增加精确 `yt4.googleusercontent.com`，以及 `i0.wp.com` 下 `/pic.4khd.com/`、`/img.4khd.com/`、`/yt4.googleusercontent.com/` 三个路径前缀。7 项 request/source policy 定向测试通过；实机“最新”8 个图集缩略图全部完成，打开 `Kiyo - Usada Pekora` 后显示 `1 / 24` 且解析完成，无“缩略图不可用/图片加载失败”。

- [x] **ONLINE-006 4KHD“最新”误用全站 SEO 分页，滚动提前到达末尾**
  证据：站点首页同时包含全站 Yoast `rel="next" -> /page/2` 和 Latest Query Block 的 `?query-3-page=2`；解析器优先选择前者后，第 3 页与前两页完全重复，Store 按重复 identity 正确终止但用户只能看到 18 个图集。
  修复目标：“最新”只跟随数值型 `query-3-page` 链路；全站 SEO `rel=next` 不得覆盖栏目分页，缺少显式 Query Block 链接时继续使用受重复页指纹保护的合成 URL。
  验收：冲突 fixture 必须选中 `?query-3-page=2`；无显式链接 fixture 合成下一页；实机连续滚动超过旧 18 项终点。
  结果：`SiteListResolver` 先解析 Latest Query Block 数值页码，仅接受带数值 `query-3-page` 的 next-button；两条冲突/回退回归测试通过。全新启动后实机滚动连续加载多页，用户复测确认恢复。

## E. Shell、UI 行为与编译质量

- [x] **UI-001 全屏状态与 split view 恢复共用标志，正常路径跳过全屏恢复**
  修复目标：独立 one-shot 标志，在窗口挂载后恢复全屏。
  验收：三栏状态有/无 × 全屏 true/false 的恢复测试或可控验证通过。
  结果：split-view 与 full-screen 使用独立 one-shot 标志；窗口挂载并恢复三栏后才按已存状态切换全屏。正常启动、侧栏/详情栏折叠恢复和源码时序检查通过。

- [x] **UI-002 ⌘0 存在“实际大小”和“切换侧栏”两套语义**
  修复目标：统一 command route，精确匹配 modifier；额外修饰键不得被吞。
  验收：⌘0/⌘1/2/3/反斜杠及带 Option/Shift 组合测试通过。
  结果：`WorkspaceKeyboardHandler` 只接收精确修饰键；⌘0 唯一执行“适合窗口”，⌘\\ 切换详情栏，⌘1/2/3 聚焦三栏。带额外修饰键不吞事件；菜单、工具栏和快捷键说明文案已统一，测试通过。

- [x] **UI-003 NSAlert 使用私有 KVC key 设置 attributed 文本**
  修复目标：改用公开 AppKit API 或 accessory view。
  验收：全项目不再命中私有 key，提示布局可用。
  结果：所有富文本提示改用公开 accessory view；全项目 KVC 私有 key 扫描无命中，Debug 构建通过。

- [x] **UI-004 Wallhaven/Favorites 等详情切换存在旧状态继承**
  修复目标：不同 source/record 进入时完整 reset page/task/error/selection state。
  验收：跨 Gallery→MissKon→Wallhaven 连续切换无旧页和错误污染。
  结果：模块/record/source 切换统一取消旧任务并重置 page、slot、error、selection 和 interaction snapshot；实机连续切换五模块未观察到旧模块内容继承。

- [x] **BUILD-001 多个 NotificationCenter 回调触发 MainActor 隔离 warning**
  修复目标：显式切回 MainActor 或采用隔离正确的观察 API；不使用无依据的 `assumeIsolated`。
  验收：Debug/Release 生产代码不再出现该组 warning。
  结果：六处滚动通知回调显式创建 `@MainActor` task 后调用 UI；增量 Debug 编译不再产生该组 warning，仅剩 Xcode AppIntents 元数据工具对无 AppIntents 依赖的环境提示。

- [x] **BUILD-002 其他编译 warning 与吞错路径**
  范围：不必要的 `nonisolated(unsafe)`、`replaceItemAt` 未使用结果、测试未使用返回值。
  验收：项目和测试 warning 清零或逐项记录有依据的保留原因。
  结果：移除无依据的吞错与未使用返回值；Debug/Release 和 XCTest 无 Swift warning。仅保留 Xcode 对未链接 AppIntents framework 的元数据工具提示，以及多架构 destination 选择提示，均非产品源码 warning。

- [x] **COMPAT-001 README 的 macOS 26+ 与工程最低 26.4 不一致**
  修复目标：做明确产品决策并同步 README、工程和 appcast；不在未验证时盲目降低 target。
  验收：三个来源一致，受支持系统完成构建/运行验证。
  结果：明确维持 macOS 26.4 最低版本；README 与工程设置一致，appcast 从最终 App 的 `LSMinimumSystemVersion` 生成。当前 macOS 26.4+ 主机 Debug 实机启动通过。

## F. 模块边界、死代码与文档

- [x] **ARCH-001 Favorites 与三个在线模块直接依赖彼此具体模型/bridge**
  修复目标：稳定的 FavoriteRecord/repository/source adapter 契约，由 App 组装注册；模块不直接调用其他业务模块。
  验收：移除任一在线 source adapter 后其他模块仍可编译运行。
  结果：新增 source-neutral `FavoriteSourceAdapter`/registry，由 App 组装注册各来源 adapter；Favorites 源码不再引用 Gallery/MissKon/Wallhaven 具体 bridge/resolver/model。全局扫描和完整构建通过。

- [x] **ARCH-002 App/Shell 的模块 switch 与具体 store 耦合面过大**
  修复目标：渐进扩充 module descriptor/command/toolbar/inspector adapter，不做一次性大重写。
  验收：新增/移除模块不要求修改大量无关 switch；路由和命令测试覆盖。
  结果：`WorkspaceModuleDescriptor.presentation` 声明工具栏、胶片条、筛选、刷新和 detail action 能力；ToolbarHost 与 CommandValidator 读取 profile，不再用 moduleID 条件链拼装工具栏。descriptor profile 测试通过。

- [x] **ARCH-003 Shared DetailPageImageCache 含 MissKon 专属 mediaFireURL**
  修复目标：业务字段迁回 MissKon 或通过模块私有 metadata 层管理。
  验收：Shared schema 无单站点业务语义，旧缓存兼容处理明确。
  结果：Shared schema 已移除 `mediaFireURL`；新增模块私有 `MissKonDetailMetadataCache` 管理 known-nil、过期和容量。旧 JSON 的额外字段由 decoder 忽略并在首次解析时重建 metadata，测试通过。

- [x] **CODE-001 FavoriteAuthorGrouping/onFavoritesChanged 等残留无生产调用**
  修复目标：确认无动态入口后删除死代码及失效测试/注释。
  验收：全局引用扫描、构建和行为测试通过。
  结果：删除 `FavoriteAuthorGrouping`、`onFavoritesChanged` 与失效测试/注释；Favorites UI 继续直接观察权威 Store。引用扫描和全量测试通过。

- [x] **CODE-002 ApifyLibrary 尝试加载不在 App target 的 expanded-ui-content 资源**
  修复目标：明确其运行职责；需要则纳入受控资源，不需要则删除失效加载路径。
  验收：启动数据来源可复现，不依赖源码相对路径。
  结果：删除不存在资源和源码相对路径 fallback；网络栏目以明确空初态启动并由首次模块 bootstrap 加载，App bundle 不再隐式依赖开发目录。

- [x] **CODE-003 Wallhaven 未使用 settings/collections API 与永不产生的 keyStorageError**
  修复目标：删除无调用代码或建立明确产品入口；保留 UserDefaults API key 作为现有产品决策，不擅自切回会弹窗的实现。
  验收：引用扫描与构建通过，设置界面错误状态与实际存储一致。
  结果：删除无产品入口的 settings/collections client、DTO/model 和 `keyStorageError` UI；保留 UserDefaults API Key 现有决策。引用扫描和构建通过。

- [x] **DOC-001 handover/README/AGENTS 状态存在版本、测试数和行为描述漂移**
  修复目标：代码与运行证据完成后同步耐久事实；避免继续堆叠回合式历史。
  验收：关键架构、模块、验证命令、支持版本和已知限制一致。
  结果：README 已同步 macOS 26.4、缓存路径和 adapter/descriptor 架构；AGENTS 已补在线策略、Favorites adapter、MissKon metadata 与 descriptor 约束；过期 8 月 14 日 handover 已替换为当前 8 月 23 日事实。

## G. 全部问题关闭后的 UI 结构全面系统审查

本阶段必须等 A–F 中功能、数据、发布和结构条目全部关闭或有明确外部门禁记录后开始。

- [x] **UI-AUDIT-001 AppKit ownership 与控制器层级**：窗口、split view、sidebar、toolbar、content/detail/inspector/download/preferences ownership 和生命周期。
  结果：AppDelegate 单一持有主窗口与四类辅助窗口；主窗口单一持有 SplitVC/ToolbarHost，SplitVC 单一持有 sidebar/content/detail host。模块 controller 由 registry 延迟创建并由 column host 替换，未发现重复窗口或 orphan controller。
- [x] **UI-AUDIT-002 三栏布局与状态恢复**：侧栏、详情栏、全屏、沉浸、live resize、最小尺寸、多显示器。
  结果：实机折叠/恢复侧栏和详情栏、切换模块、重启恢复宽度均正常；全屏恢复与三栏恢复标志已拆分，离屏窗口会移回当前可见屏幕。沉浸模式退出会恢复进入前的 sidebar/content/detail 状态。
- [x] **UI-AUDIT-003 五模块行为一致性**：列表/网格、选择、双击、键盘、右键、搜索、分页、footer、详情、胶片条。
  结果：实机依次检查 Local/Favorites/Wallhaven/4KHD/MissKon 的空态或数据态、选择、详情、工具栏、搜索、列表/网格与胶片条可用性；共享 table/collection/card/waterfall/keyboard 基类覆盖一致行为，状态机差异留在模块内。
- [x] **UI-AUDIT-004 NSToolbar 与菜单命令**：item identity、validation、快捷键、来源筛选、保存/信息、列数和布局状态。
  结果：工具栏 item 集合改由 descriptor profile 决定；实机发现并修复 Wallhaven 同时出现独立保存/信息与重复“操作”菜单、空本地图库仍启用大图模式、校验层覆盖 isEnabled，以及“实际大小/适合窗口”文案不一致。显示菜单与工具栏最终 identity/validation 一致。
- [x] **UI-AUDIT-005 Inspector/Preferences/Downloads 辅助窗口**：同步、关闭语义、重复创建、焦点和状态持久化。
  结果：三类窗口均实机打开、关闭、重新打开；Inspector/Downloads utility panel 关闭为隐藏并复用，Preferences 由 AppDelegate 复用。Inspector 异步字段更新、Downloads 空态/禁用按钮、Preferences 滚动布局均正常。
- [x] **UI-AUDIT-006 可访问性与系统语义**：VoiceOver labels、键盘遍历、system controls、菜单角色、对比度和动态外观。
  结果：使用系统 AX 树检查侧边栏、五模块 collection/table、toolbar、splitter、辅助窗口和菜单；列表/网格与 card 增加中文 label，Inspector 全字段中文化，缺图 icon 增加描述。交互控件继续使用 AppKit 原生 role、validation 和焦点链。
- [!] **UI-AUDIT-007 视觉与性能验证**：滚动复用、错图、闪烁、布局跳动、CPU/内存、缓存命中、10k/50k 本地图库。
  结果：现有在线数据实机滚动与模块切换未见错图/持续布局跳动；复用身份、可取消图片任务、prefetch、diffable data source、有界缓存和 single-flight prune 已有代码与测试证据。实机日志出现的 `Invalid view geometry` 已用 LLDB 在 `_os_log_fault_impl` 捕获调用栈，来源为 AppKit `NSThemeFrame._positionSharingIndicator → NSWindowSharingSessionRecipientIndicator`，由 UI 检查工具的窗口选择性共享触发，栈中无项目视图代码，因此排除为 4KHD 布局问题。仓库没有可合法分发的 10k/50k 本地图库 fixture，本轮未伪造图像性能结论；最终大图库 CPU/内存/帧率仍需指定真实数据集和 Instruments 基线。
- [x] **UI-AUDIT-008 UI 结构结论与整改记录**：形成结构图、发现清单、修复结果、残余人工验收项。
  结果：结构与整改记录如下；除大图库性能基线及发布环境 UI/更新验收外，本轮新发现的可复现 UI 问题均已修复。

### UI ownership 结构

```text
FourKHDAppDelegate
├─ WorkspaceWindowController
│  ├─ WorkspaceToolbarHost ← WorkspaceModuleDescriptor.presentation
│  └─ WorkspaceSplitViewController
│     ├─ WorkspaceSidebarViewController
│     ├─ WorkspaceColumnHostController (content)
│     │  └─ 当前模块 ContentViewController
│     └─ WorkspaceColumnHostController (detail)
│        └─ 当前模块 DetailViewController
├─ WorkspaceInspectorWindowController  (复用/关闭隐藏)
├─ WorkspaceDownloadsWindowController  (复用/关闭隐藏)
├─ WorkspacePreferencesWindowController (复用)
└─ WorkspaceKeyboardShortcutsWindowController (复用)
```

### UI 审查中新发现并修复

| 编号 | 发现 | 修复与复验证据 |
|---|---|---|
| UI-FIND-001 | descriptor 重构后 Wallhaven 仍带 `detailActions: .wallhaven`，与独立保存/信息按钮重复 | profile 改为 `.none`；实机工具栏只保留筛选、收藏、保存原图、显示信息 |
| UI-FIND-002 | 无本地目录时列数、大图模式仍可能可用 | Local snapshot 按 `hasLocalRoot` 门控列数；大图模式同时按 current reference 门控 update 与 validation |
| UI-FIND-003 | Inspector 字段和 module label 大量英文 | 全部字段、状态、Yes/No、路径/链接中文化；实机 AX 树显示“未选择项目 本地图库…” |
| UI-FIND-004 | 列表/网格 AX label 使用英文，card 缺少聚合名称 | 五模块容器和侧边栏改为中文 label；共享 card 按标题+metadata 暴露可访问名称 |
| UI-FIND-005 | `⌘0` 实际执行 fit，但菜单/快捷键窗口写“实际大小” | 统一为“适合窗口”，命令 action 与 toolbar 语义一致 |
| UI-FIND-006 | Wallhaven detail metadata 显示 `Category: people` | 分类标签和 category title 中文化 |
| UI-FIND-007 | 内容/详情列在 `NSScrollView` 与窗口之间又叠了两层强制 `.active` 的 `.contentBackground` 材质，Shell 同时叠加全窗口 `.titlebar` 材质并强制 `.unified`；破坏 AppKit 对滚动视图与浮动工具栏的自动滚动边缘效果，导致激活时背景消失、悬停/失焦时才出现，折叠详情列时还会短暂暴露受图片染色的材质 | 删除 Shell 和 column host 中的人工材质层，恢复纯 `NSView` 宿主与窗口默认 `.automatic` toolbar style；保留 `.fullSizeContentView`、内容顶边对齐及 `automaticallyAdjustsContentInsets = true`。实机复验滚动内容继续穿过工具栏下方，激活/悬停/失焦的系统边缘材质保持连续，详情列开关后无绿色暴露 |

排除项：UI 检查期间的负尺寸 runtime issue 来自 macOS 窗口共享指示器，不进入 4KHD 视图代码；保留调用栈证据，不以猜测修改业务布局。

### UI 结论

- 三栏 ownership 清晰，未发现第二套 UI runtime、跨模块直接嵌套 controller 或辅助窗口重复创建。
- 一致能力已经集中到 AppKit 系统控件、Shared UI 基类、toolbar snapshot 与 descriptor profile；模块差异主要保留在业务 Store/Resolver。
- 当前最值得继续投入的不是大规模重写，而是建立固定真实大图库的 Instruments 性能基线，以及在每次发布候选 DMG 上重跑 AX/窗口/自动更新冒烟流程。

## 最终验收

- [x] Debug build 通过。
- [x] Release build 通过。
- [x] 全部 XCTest 通过：82/82，0 failure、0 skipped。
- [x] 生产代码 0 SwiftUI。
- [x] `git diff --check` 通过。
- [!] 最终 DMG entitlement、签名、公证、版本、架构、Sparkle 签名门禁：代码门禁、受保护环境和真实 Sparkle EdDSA Secret 已就绪；仍需由实际发布流水线生成并验证最终签名/公证 DMG，不能把本地 Release 样本冒充发布产物。
- [!] N-1 自动更新安装：Installer Launcher 与 entitlement 代码已配置；仍需真实签名发布包和受保护发布环境实测。
- [x] UI 结构审查完成；可复现的新问题均已修复，窗口共享工具产生的 AppKit runtime issue 已用调用栈排除。
- [x] AGENTS.md、README.md、当前 handover 与本文件同步。

## 执行记录

- 2026-08-23：创建清单。基线来自当前源码、50 项 XCTest、Release 构建和已发布 1.8.5 DMG 的只读检查；尚未开始修复。
- 2026-08-23：完成发布链代码修复和本地签名 Release 样本权限验证；配置 4KHD 专属 Sparkle EdDSA Secret，并建立仅允许 `main`、要求仓库所有者审批的 GitHub `release` environment。最终签名/公证产物和 N-1 自动升级由实际发布继续验收。
- 2026-08-23：完成用户数据与持久权限批次；新增 7 个相关回归场景，定向测试全部通过。
- 2026-08-23：完成图片、缓存与本地扫描批次；新增 5 个回归场景，定向测试全部通过；同时关闭 NotificationCenter 的 MainActor 编译警告。
- 2026-08-23：完成在线状态机、URL 安全、Shell/UI、模块边界和文档批次；完成五模块、三栏、工具栏、菜单、辅助窗口、可访问性与全屏/沉浸的实机 UI 审查。
- 2026-08-23：用户报告 4KHD 无法加载新图集。定位为当前媒体链 `img.4khd.com → i0.wp.com/yt4.googleusercontent.com/...` 被重定向守卫误拒；按精确主机和代理路径修复并新增回归测试。实机最新列表缩略图全部加载，`Kiyo - Usada Pekora` 24 张详情图解析完成。
- 2026-08-23：用户报告工具栏非悬停时系统背景消失、折叠详情列闪绿。确认不应用 safe area 截断内容；删除遮在 `NSScrollView` 外的多层自定义材质和显式 `.unified` 窗口样式，让 AppKit 默认 scroll-edge effect 接管。实机滚动、悬停、失焦及详情列开关复验通过，内容仍可穿过工具栏下方。
- 2026-08-23：用户报告 4KHD“最新”滚动无法加载下一页。定位为首页全站 SEO `/page/N` 与栏目 Query Block `?query-3-page=N` 并存时选错分页链；改为优先且仅接受数值型 Query Block 分页，冲突 fixture、回退 fixture、定向状态机测试和实机连续多页滚动通过，用户复测确认恢复。
- 2026-08-23：最终 Debug/Release 构建、82 项 XCTest、0 SwiftUI、脚本语法与 `git diff --check` 全部通过。外部仅剩实际流水线生成的最终签名/公证 DMG、N-1 更新安装和指定 10k/50k 数据集的 Instruments 基线。
