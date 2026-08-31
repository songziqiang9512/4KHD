# 4KHD

4KHD 是一款 macOS 原生图片与媒体图库工作区，用于浏览在线图集、站点视频和本地图片目录。

**纯 AppKit 实现**：主窗口、三栏工作区、侧边栏、工具栏、中栏列表/网格、详情区、胶卷条全部由 AppKit 原生控件承载。生产代码 0 SwiftUI。

## 功能

### 在线图库 — 4KHD Gallery
- 浏览 4KHD 网站栏目（最新、推荐、Cosplay、写真）
- 列表/网格双视图，封面缩略图 + 标题 + 元信息
- 后台解析详情页提取原图地址
- 图集浏览到末尾后继续翻页，显示原站推荐图集
- 搜索高亮、收藏集成、Inspector 信息展示

### 在线图库 — MissKon
- 浏览 misskon.com 内容（最新、热门、Cosplay、AI 生成、私房摄影、秀人、花漾）
- 列表/网格双视图，分页加载，按 section 磁盘缓存
- 渐进式详情加载：首页立即解析展示，后台按需加载后续页
- 胶片条占位 + 按页序填充，失败页自动移除
- 封面→大图过渡，相邻图片预加载
- 图集浏览到末尾后继续翻页，以整齐网格显示原站 6 个推荐图集
- 搜索高亮+debounce、收藏集成、Inspector 信息展示

### 在线图库 — Wallhaven
- 浏览 wallhaven.cc 壁纸（分类/排序/比例/分辨率筛选）
- 纯度门控（无 API Key 仅 SFW）
- 上传者作品浏览（API @username 搜索 + HTML 抓取回退）
- 详情缓存（内存+磁盘），预览→原图升级
- 设为桌面壁纸、收藏集成

### 在线图库 — 爱妹子
- 侧边栏分为「最近更新 / 妹子图 / 排行榜 / 影片花絮」；妹子图默认丝袜美女，排行榜默认最受欢迎
- 妹子图工具栏提供 10 个一级类型及当前类型的相关专题（合计 25 个）；排行榜精确提供 6 个原站排行入口
- 列表/瀑布流双布局，搜索与各入口支持真实分页；详情只在可见时逐页解析，HTML/JSON 解析不占用 UI 主线程
- 详情区提供缩放、导航、计数、底部胶片条和沉浸模式；最后一张继续向后翻页显示原站推荐图集
- 自动识别含视频图集；HLS 视频使用独立原生 `AVPlayerView` 窗口播放，详情播放按钮和播放器画面的右键菜单都可直接保存 MP4 或拷贝影片源 URL
- 详情解析到真实视频源后，工具栏「保存」菜单可将 MPEG-TS HLS（含 AES-128 VOD）解密后无损封装并保存为 MP4；视频进入与整图集共用的非模态下载任务中心，显示已下载/总大小、整体百分比和速度并支持取消，完成前不会覆盖目标文件
- 普通请求遇到站点验证时才显示 WebKit 验证窗口，并同步站点 Cookie 后重试；验证窗口的主框架跳转始终限制在受信任站点，视频保存流程整次最多恢复一次验证，不会无限重试
- 收藏、整图集下载、Inspector 与沉浸式图片详情已接入统一工作区

### 在线图库 — 每日大赛
- 侧边栏为「最近更新」加原站 20 个分类；列表/瀑布流双布局，搜索与分类使用站点真实分页
- 详情区提供缩放、导航、计数、底部胶片条和沉浸模式；图片来自详情页 `data-xkrkllgl`（CDN 密文需按原站算法解密），最后一张继续向后翻页显示相邻推荐
- 解析到 HLS 后可用独立原生窗口播放、拷贝影片源 URL，并保存为 MP4（AES-128 清单先解密 TS 再封装）
- 收藏、整图集下载、Inspector 已接入统一工作区

### 在线视频 — QuanjiGallery
- 侧边栏分类入口；列表/瀑布流双布局，搜索与分页使用站点公开 HTML
- 无右侧详情栏。双击或右键「播放」打开独立原生窗口；右键「下载视频」将公开 HLS 保存为 MP4

### 在线视频 — PornyGallery
- 侧边栏分类入口；列表收录 `/video/view/` 与 `/video/viewhd/` 卡片，跳过外域广告
- 无右侧详情栏。只播放公开观看页中的 `data-src`；`viewhd` 卡片改解析同一 id 的 `/video/view/`。不伪造登录态

### 图片详情
- 触控板缩放/平移、鼠标位置为中心缩放
- 上/下张键盘/浮层按钮导航，Escape/Tab/Enter 键盘支持
- 窗内大图模式（自动隐藏工具栏和胶卷条）
- 底部缩略图胶卷条（4KHD/MissKon/爱妹子/每日大赛及其在线收藏详情）
- 4KHD/MissKon/爱妹子/每日大赛及对应在线收藏的图集尾页推荐，可直接进入来源模块的推荐图集
- 保存图片、重置缩放

### 本地图片
- 目录导入、扫描、metadata 读取
- 瀑布流网格 / 列表双视图
- 详情浏览、Quick Look、Finder 定位
- 设为桌面壁纸
- 搜索匹配文件名和文件夹名，结果高亮

### 收藏（在线收藏）
- 「本地」分组内的「在线收藏」节点，汇总 4KHD / MissKon / Wallhaven / KnitGallery / MrdsGallery / QuanjiGallery / PornyGallery 的收藏
- 工具栏按来源筛选（全部及各在线模块）与搜索
- 列表 / 瀑布流网格双布局（与 MissKon/4KHD 相同的卡片、hover、双击交互）；图集来源的详情区为大图查看区（缩放、胶片条、沉浸模式）
- 持久保存于 FavoritesStore（favorites.json）；旧版本收藏数据按 detailURL host 自动兼容
- Gallery / MissKon / 爱妹子 / 每日大赛来源的收藏项可「保存整个图集」与「保存当前图片」
- Gallery / MissKon / 爱妹子 / 每日大赛来源的收藏详情在图集末尾显示推荐，点击后路由到对应在线模块
- 4KHD / MissKon / 爱妹子 / 每日大赛收藏详情复用来源模块的解析、胶片条、相邻预取与页尾推荐；关闭或切换详情会取消旧解析，分页严格沿连续前缀串行推进，失败可点击重试且不会提前进入推荐
- 收藏筛选为空或删除当前项目时会清空旧详情；历史封面会按所属来源重新校验，分页失败可从原位置重试且不会提前显示推荐
- 爱妹子含视频收藏在详情中提供播放、空格键播放、影片源 URL 复制及工具栏 MP4 保存，启用状态来自当前已解析视频而不是列表提示
- 每日大赛含视频收藏可播放、拷贝影片源 URL，并保存为 MP4（AES-128 HLS 先解密再封装）
- QuanjiGallery / PornyGallery 收藏不打开详情栏：双击播放，右键「播放」「下载视频」
- MissKon 收藏详情保留 MediaFire 资源入口
- Wallhaven 收藏详情加载原图和完整元数据，可设为壁纸、浏览同来源收藏的上一张/下一张，并从上传者入口在应用内进入 Wallhaven 对应作品列表

### 设置
- 统一布局切换（列表/网格，同时控制各在线图库、在线视频模块与本地图库）
- 在线缓存容量选择（512MB-4GB/无限制）
- 一键清除所有缓存（图片、详情页、模块数据、临时文件）
- 侧边栏模块显示开关覆盖各在线图库与在线视频模块
- 收藏 JSON 导出/导入覆盖全部合法在线来源；导入会拒绝非受信来源，并安全合并重复记录
- 发布版每天自动检查更新，也可从应用菜单选择“检查更新…”

### 辅助窗口
- 下载窗口统一显示图集与视频任务，单一标题下提供队列摘要、已下载/总大小、整体百分比、当前/平均速度、取消、完成清理和 Finder 定位；运行中总量可为估算值，完成后以真实落盘大小校正，窗口关闭后任务继续
- 信息窗口按来源显示图标、标题、概览、资源和来源分组；长标签、描述和链接可滚动查看，缺失字段不会以成排横线占位

## 架构

```
4KHD/
  App/          — 应用入口、偏好设置、Inspector、下载管理器与独立视频播放器
  Shell/        — 三栏工作区、侧边栏、工具栏、模块路由与展示能力描述符
  Shared/       — 跨模块能力（图片缓存、统一下载队列、键盘处理、UI 组件、共享基类）
  Modules/
    4KHDGallery/ — 4KHD.com 在线图库
    MissKon/    — misskon.com 在线图库
    Wallhaven/  — wallhaven.cc 在线壁纸
    KnitGallery/ — xx.knit.bid 图片与视频图库
    MrdsGallery/ — www.mrds66.com 每日大赛图库
    QuanjiGallery/ — 在线视频列表与公开 HLS
    PornyGallery/ — 在线视频列表与公开 HLS
    LocalLibrary/ — 本地图片
    Favorites/  — 收藏记录
4KHDTests/      — XCTest 回归测试
```

Shell 通过 `WorkspaceModuleDescriptor` 组装每个模块的 content/detail controller 与工具栏能力；Favorites 通过 App 注册的 source adapter 使用各在线源能力，业务模块之间不直接引用具体实现。

维护边界见 `AGENTS.md`；当前实现与验证状态见 `docs/ai-handover-2026-09-01.md`；发布操作见 `docs/release-process.md`；1.9.1 用户可见改动见 `docs/releases/1.9.1.md`。

## 开发

### 环境
- macOS 26.4+
- Xcode 26+
- Swift 6
- AppKit
- Swift Package Manager（Nuke、Sparkle）

### 构建

```bash
open 4KHD.xcodeproj
# 或
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build

# 回归测试
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -destination 'platform=macOS' test
```

### 设计原则

1. 优先使用 macOS 系统原生 API（NSToolbar、NSSplitViewController、NSCollectionView、NSVisualEffectView）
2. 不自定义绘制，不引入第三方 UI 框架
3. 50 行能搞定的功能绝不写 200 行
4. 模块间零直接依赖，通过 Shared 层共享能力

### 验证 0 SwiftUI

```bash
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
```

## 缓存

- Gallery 详情页解析结果：`~/Library/Application Support/4KHD/DetailPageCache/pages.json`
- MissKon 列表缓存：`~/Library/Application Support/4KHD/MissKon/feed-cache.json`
- MissKon 详情 metadata：`~/Library/Application Support/4KHD/MissKon/DetailMetadata/pages.json`
- Wallhaven 详情缓存：`~/Library/Application Support/4KHD/Wallhaven/detail-cache.json`
- 本地缩略图：`~/Library/Caches/4KHD/LocalImageThumbnails/`（最多 1GB / 20,000 文件；旧 Application Support 目录会迁移或清理）
- 在线图片：Nuke 管线管理（288MB / 700 项内存缓存 + 单一可配置磁盘缓存）
- 收藏记录：`~/Library/Application Support/4KHD/favorites.json`；写入前保留 `favorites.json.bak`，主文件损坏时自动恢复
- Wallhaven API Key：UserDefaults 存储

在线模块在首次进入时才启动网络加载，未打开的模块不会在应用启动阶段抢占请求和解码资源。

## 注意事项

- 软件依赖目标网站当前 HTML 结构，结构变化可能需要调整解析规则
- 在线列表、搜索和详情解析失败会在列表 footer（可点击重试）或详情状态条中显示错误
- 图片内容运行时从网站读取，不随仓库分发
- 请遵守来源网站的访问规则和使用限制
- 已知 UI 边界：顶部系统工具栏的 scroll-edge 半透明背景在部分三栏/详情栏状态下仍可能异常；内容穿过系统工具栏下方仍是预期行为，当前没有用 safe-area 截断或自绘背景规避
