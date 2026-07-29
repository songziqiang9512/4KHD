# 4KHD AI Handover — 2026-07-28

## 本轮结论

项目已切换到 Swift 6，并新增 `4KHDTests` 单元测试 target。生产代码仍为纯 AppKit，未引入 SwiftUI。

## 已修复

- Shell 的统一列表/网格切换现覆盖 Gallery、LocalLibrary、MissKon、Wallhaven；列数菜单校验也覆盖全部模块。
- 在线模块改为首次进入时 bootstrap，启动阶段不再同时刷新三个在线源。
- Wallhaven 上传者 HTML 回退会区分 2xx、401、404、429 与其他 HTTP 错误。
- 在线图片磁盘缓存收敛为 Nuke DataCache 单层；清除缓存会停止预取并清空 Nuke 内存/磁盘状态。
- 本地缩略图同步查询只访问内存，磁盘读取与解码在后台执行；预取限制到可见窗口附近、最多 4 路并发。
- 本地缩略图磁盘缓存增加 1GB / 20,000 文件上限；清除缓存会等待进行中的加载结束后再删除目录。
- MissKon 与 Wallhaven 缓存写入改为串行后台队列，清除操作与待写入任务保持顺序。
- 移除 Gallery 从源码目录读取开发样本 JSON 的回退，只允许读取应用 bundle 中的资源。
- 删除无用的本地详情 metadata 加载与 2 秒文件可用性轮询。
- 移除入站网络 entitlement 和临时 TLS 1.0 / HTTP ATS 例外。
- Release 不再强制 ad-hoc 签名；显式 entitlement 文件保留沙盒/出站网络/用户文件权限，同时排除 `get-task-allow`，硬化运行时可正常生效。
- 4KHD/MissKon 普通列表在零条目匹配时会报告页面结构解析失败；搜索只有出现明确空结果标记时才接受空列表。MissKon 的显式下一页链接不再因当前页空结果被抹掉。
- Wallhaven 上传者回退会保留 API 搜索错误；HTML 找到作品但详情全部失败时会进入错误/重试状态，不再伪装成“没有作品”。
- 收藏改为后台加载与写盘，切换收藏先持久化成功再发布内存状态；导入、导出及写入失败会给出明确 UI 反馈。
- 详情页缓存改为后台预载并使用加载代次阻止清理前快照复活；本地缩略图清理期间暂停新加载，并拒绝旧代次任务回写。
- 本地列表/网格的同步缓存查询不再读取文件属性；文件版本来自后台 metadata，缺失时由 `LocalImageCache` actor 在后台解析。
- 在线模块 bootstrap 使用各 Store 的幂等入口；路由先应用目标栏目，再按需启动网络请求，避免首次进入时取消并重发同一请求。
- 新增 Sparkle 2.9.x 更新入口：发布版每天检查 GitHub `update-feed/appcast.xml`，应用菜单提供“检查更新…”，Debug 构建只显示不执行更新的提示；发布工作流负责生成并发布 appcast。

## 验证

- Debug XCTest：13/13 通过。
- Swift 6 Debug build：通过。
- `4KHDTests` 当前覆盖路由序列化、请求头契约、模块 bootstrap 幂等性、列表解析失败、空搜索分页、收藏迁移/回调/持久化成功/失败和详情缓存清理代次。

## 后续维护约束

- 新增模块时，同时接入 `WorkspaceToolbarContext` 的统一布局/列数命令。
- 不要把 URLCache 恢复为第二套在线图片磁盘缓存。
- 缓存写入不得在 MainActor 上执行，也不得绕过各 Store 的 `clearCache()`。
- 普通在线列表零匹配不得更新缓存时间；搜索空结果必须由页面中的明确空状态标记确认。
- 收藏 UI 状态只能在持久化成功后更新，失败必须保留原状态并提示用户。
- 需要扩展网络兼容性时，先确认具体 HTTPS 失败证据；不要恢复宽泛 ATS 例外。
