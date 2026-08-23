# 4KHD

4KHD 是一款 macOS 原生图片浏览软件，用于浏览在线图库内容和本地图片目录。

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

### 图片详情
- 触控板缩放/平移、鼠标位置为中心缩放
- 上/下张键盘/浮层按钮导航，Escape/Tab/Enter 键盘支持
- 窗内大图模式（自动隐藏工具栏和胶卷条）
- 底部缩略图胶卷条（MissKon/Gallery）
- 4KHD/MissKon 图集尾页推荐，可直接进入推荐图集
- 保存图片、重置缩放

### 本地图片
- 目录导入、扫描、metadata 读取
- 瀑布流网格 / 列表双视图
- 详情浏览、Quick Look、Finder 定位
- 设为桌面壁纸
- 搜索匹配文件名和文件夹名，结果高亮

### 收藏（在线收藏）
- 「本地」分组内的「在线收藏」节点，汇总 4KHD / MissKon / Wallhaven 三个模块的收藏
- 工具栏按来源筛选（全部 / 4KHD / MissKon / Wallhaven）与搜索
- 列表 / 瀑布流网格双布局（与 MissKon/4KHD 相同的卡片、hover、双击交互）；详情区为大图查看区（缩放、胶片条、沉浸模式）
- 持久保存于 FavoritesStore（favorites.json）；旧版本收藏数据按 detailURL host 自动兼容
- Gallery / MissKon 来源的收藏项可「保存整个图集」与「保存当前图片」
- Gallery / MissKon 来源的收藏详情在图集末尾显示推荐，点击后路由到对应在线模块

### 设置
- 统一布局切换（列表/网格，同时控制所有模块）
- 在线缓存容量选择（512MB-4GB/无限制）
- 一键清除所有缓存（图片、详情页、模块数据、临时文件）
- 侧边栏模块显示开关（4KHD/MissKon）
- 发布版每天自动检查更新，也可从应用菜单选择“检查更新…”

## 架构

```
4KHD/
  App/          — 应用入口、偏好设置、Inspector
  Shell/        — 三栏工作区、侧边栏、工具栏、模块路由与展示能力描述符
  Shared/       — 跨模块能力（图片缓存、键盘处理、UI 组件、共享基类）
  Modules/
    4KHDGallery/ — 4KHD.com 在线图库
    MissKon/    — misskon.com 在线图库
    Wallhaven/  — wallhaven.cc 在线壁纸
    LocalLibrary/ — 本地图片
    Favorites/  — 收藏记录
4KHDTests/      — XCTest 回归测试
```

Shell 通过 `WorkspaceModuleDescriptor` 组装每个模块的 content/detail controller 与工具栏能力；Favorites 通过 App 注册的 source adapter 使用各在线源能力，业务模块之间不直接引用具体实现。

详见 `AGENTS.md`。

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
- 在线图片：Nuke 管线管理（384MB 内存缓存 + 单一可配置磁盘缓存）
- 收藏记录：`~/Library/Application Support/4KHD/favorites.json`；写入前保留 `favorites.json.bak`，主文件损坏时自动恢复
- Wallhaven API Key：UserDefaults 存储

在线模块在首次进入时才启动网络加载，未打开的模块不会在应用启动阶段抢占请求和解码资源。

## 注意事项

- 软件依赖目标网站当前 HTML 结构，结构变化可能需要调整解析规则
- 在线列表、搜索和详情解析失败会在列表 footer（可点击重试）或详情状态条中显示错误
- 图片内容运行时从网站读取，不随仓库分发
- 请遵守来源网站的访问规则和使用限制
