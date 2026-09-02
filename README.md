# 4KHD

macOS 原生桌面工作区，用于浏览在线媒体和本地图片目录。

生产界面全部是 AppKit。不使用 SwiftUI。

## 能力

- 三栏工作区：侧边栏、列表/网格、可选详情栏
- 系统工具栏、下拉刷新、键盘导航
- 图集详情：缩放、相邻导航、胶片条、窗内大图
- 独立窗口播放 HLS，视频进入统一下载队列并可保存为 MP4
- 本地目录导入、扫描、Quick Look、设为壁纸
- 跨来源收藏、偏好设置、缓存清理、自动更新

模块可独立开关。未进入的在线模块不会在启动时抢占网络。

## 结构

```
4KHD/
  App/       入口、偏好设置、Inspector、下载窗口、独立播放器
  Shell/     底壳、路由、三栏布局、侧边栏、工具栏
  Shared/    至少两个模块共用的能力
  Modules/   业务模块（模块间不直接依赖）
4KHDTests/   XCTest
```

维护边界见 `AGENTS.md`。发布流程见 `docs/release-process.md`。

## 模块

| 模块 | 说明 |
|------|------|
| `4KHDGallery` | 4KHD.com 图集 |
| `MissKon` | misskon.com 图集 |
| `Wallhaven` | wallhaven.cc 壁纸 API |
| `KnitGallery` | xx.knit.bid 图集与 HLS |
| `MrdsGallery` | www.mrds66.com 图集与 HLS |
| `QuanjiGallery` | 91quanji.com 视频 |
| `PornyGallery` | 91porny.com 视频 |
| `TangxinGallery` | tangxinvlog.app 视频 |
| `TaiavGallery` | taiav.com 视频 |
| `LocalLibrary` | 本地图片目录 |
| `Favorites` | 跨来源收藏 |

视频模块声明 `showsDetailPane: false`：双击或右键播放，右键下载，不打开详情栏。

## 数据位置

应用启用 App Sandbox。`FileManager` 的 Application Support / Caches / Preferences 解析到容器内：

```text
~/Library/Containers/com.songziqiang.-KHD/Data/
```

下文路径均相对该容器的 `Library/`。菜单「打开 Application Support / 图片缓存」也指向容器内目录。本地导入目录和下载落盘目录在容器外，靠安全作用域书签访问。

### Application Support

`Application Support/4KHD/`

| 路径 | 用途 | 归属 |
|------|------|------|
| `favorites.json` | 收藏记录。写入时保留 `favorites.json.bak` | Favorites |
| `DetailPageCache/pages.json` | 详情页图片 URL / 分页 / 推荐，7 天过期 | 4KHDGallery、MissKon、KnitGallery、MrdsGallery |
| `MissKon/feed-cache.json` | 列表分区磁盘缓存 | MissKon |
| `MissKon/DetailMetadata/pages.json` | 来源专属详情 metadata，不写入共享详情缓存 | MissKon |
| `Wallhaven/detail-cache.json` | 已解析壁纸详情 | Wallhaven |

4KHDGallery、KnitGallery、MrdsGallery 以及全部视频模块的**列表**只放在内存，进程退出即丢。下载队列同样不落盘；已写入用户选定目录的文件保留。

### Caches

| 路径 | 用途 | 归属 |
|------|------|------|
| `Caches/com.songziqiang.4khd.images/` | Nuke `DataCache`。在线缩略图与详情图。容量由偏好设置 512MB–4GB / 无限制 | 全部在线模块与收藏封面 |
| `Caches/4KHD/LocalImageThumbnails/` | 本地目录缩略图。旧位置 `Application Support/4KHD/LocalImageThumbnails/` 会迁移到这里 | LocalLibrary |
| `Caches/4KHD-KnitVideo/` | HLS 分片、密钥与封装工作目录。未完成分片可续传 | KnitGallery、MrdsGallery、QuanjiGallery、PornyGallery、TangxinGallery、TaiavGallery |

设为壁纸的临时文件写在系统临时目录下的 `4KHD-Wallpaper/`。Cookie 由 `HTTPCookieStorage.shared` 与 `WKWebsiteDataStore` 保存在容器内 `HTTPStorages/`、`WebKit/`。Sparkle 更新状态也在容器内，由框架管理。

「清除缓存」会清 Nuke 磁盘缓存、上述详情/列表磁盘缓存、本地缩略图缓存和临时文件，不会删除 `favorites.json` 或本地导入书签。

### Preferences

`Preferences/com.songziqiang.-KHD.plist`（`UserDefaults`）

| 内容 | 归属 |
|------|------|
| 窗口分栏、侧边栏展开、当前路由、详情栏、胶片条、Inspector 是否打开 | 底壳 |
| 各模块列表/网格与网格列数 | 对应模块 |
| 高级模块侧边栏开关 | 底壳 |
| 在线图片缓存容量上限 | 共享图片管线 |
| 上次图集/视频保存目录 | 下载 |
| 本地根目录安全作用域书签、排除目录、排序 | LocalLibrary |
| API Key、纯度、分类/排序/分辨率/比例 | Wallhaven |

收藏记录已迁出 UserDefaults；旧键仅用于一次性迁移。

## 开发

- macOS 26.4+
- Xcode 26+
- Swift 6
- 依赖：Nuke、Sparkle

```bash
open 4KHD.xcodeproj

xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -configuration Debug build
xcodebuild -scheme 4KHD -project 4KHD.xcodeproj -destination 'platform=macOS' test
```

```bash
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
```

优先用系统控件。能短则短。新增模块不改底壳，删除模块不影响其他模块。

## 说明

- 在线内容按当前站点页面解析，结构变化需要改解析
- 媒体不随仓库分发
- 请遵守来源站点的访问规则
