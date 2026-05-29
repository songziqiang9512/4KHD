# 4KHD 在线模块稳定性与体验优化报告（最终版）

**日期**: 2026-05-29 ~ 2026-05-30  
**范围**: 全 7 模块 — MissKon、Wallhaven、4KHDGallery、Favorites、Shared、Shell、App  
**提交**: 37 commits（第二轮起），36 文件，+1500/-400 行  
**编译**: 全部通过，零 error 零 warning，零 SwiftUI 命中  

---

## 一、关键架构变更

### Wallhaven — 请求状态机

```
listRequestToken (UUID)
├── beginListRequest() — 每个网络请求入口生成新 token
├── invalidateListRequests() — 取消/切换路径递增 token 使旧 Task 失效
├── Task 写入前: guard listRequestToken == requestToken && section/query checks
├── Task catch 前: guard listRequestToken == requestToken && section/query checks
└── Task 完成清理: guard listRequestToken == requestToken
```

### MissKon — 渐进式详情解析

```
prepare(item) → 生成 imageCount 个占位 slot + coverURL 首槽
resolve(item) → 仅解析第 1 页 + prefetch 2 页
用户翻到尾部 → ensureNextDetailPageLoadedIfApproachingEnd(from:) 
              → maxResolvedDisplayIndex - 4 阈值
              → loadNextUnresolvedPage()
用户点占位 slot → ensurePageLoadedForSlot(at:) → 立即加载该页
pageTasks: [URL: Task] — 每页独立在途任务
mergeResolvedPage → 完全替换该 pageURL 的 slots
removeSlots(forFailedPage) → 移除失败页的占位 slots
```

### refreshFromNetwork — 模式路由

```
Wallhaven:
  section == .favorites → refreshFavorites()
  isBrowsingUploader → uploader page 1 重载 (保持 uploader 模式)
  activeSearchQuery 非空 → submitSearch(query, force: true)
  否则 → 普通 browse refresh

MissKon:
  section == .favorites → restoreSectionCache()
  activeSearchQuery 非空 → submitSearch(query, force: true)
  否则 → 普通 section refresh

Gallery:
  activeSearchQuery 非空 → submitSearch(force: true)
  否则 → 普通 section/network refresh
```

---

## 二、完整修复日志

| 提交 | 模块 | 修复内容 |
|------|------|----------|
| `d6f5401` | Wallhaven | Uploader 并行、429 重试、searchLoadTask 分离、搜索翻页路由 |
| `a6e5113` | MissKon | searchLoadTask 分离、搜索 debounce、分页 guard、cache 裁剪 |
| `e123a71` | MissKon | 滚动位置记忆、详情进度、prefetch 停止 |
| `f5fbb1e` | Wallhaven | 上传者结果保序 |
| `294aa20` | Shared+Shell+Gallery | WaterfallLayout didLayoutAllItems、bootstrap 顺序、图标互换、RemoteImageView guard、regex 缓存、重试循环、字典泄漏 |
| `61e6df0` | Gallery+Shared | ZoomableImageView re-fit、GridCard resetForReuse |
| `507ba4d` | MissKon+Wallhaven | 延迟详情解析、图片升级、purity 门控、load gate、refresh 顺序 |
| `27d1e0e` | MissKon+Wallhaven | cancelResolution、retry guard、task lifecycle、in-flight 清理 |
| `1b80e1a` | MissKon+Wallhaven | 恢复解析、失败重试 UI、request token |
| `8be1b3f` | MissKon+Wallhaven | 每请求独立 token、resolve gate |
| `bdf2b0d` | Wallhaven | token-guard 状态写入 |
| `80eba69` | MissKon+Wallhaven | detail identity guard、search sync、frozen params |
| `73ba2c2` | MissKon+Wallhaven | retry 失败 detail、sync isRefreshing、in-flight on refresh |
| `16c02e1` | MissKon+Wallhaven | refreshFromNetwork 模式路由 |
| `dd0bc0d` | Wallhaven | uploader 参数快照、task 清理 |
| `667dc72` | Wallhaven+Gallery | detail apiKey freeze、search force+identity guard |
| `b628402` | Gallery | cancel guard、search isolation |
| `023f0f0` | Gallery | 键盘、底部重试、搜索高亮 |
| `771733c` | MissKon+Wallhaven | API Key UserDefaults、渐进详情、胶片条占位 |
| `fa00f0c` | MissKon+Wallhaven | pageTasks 状态机、Keychain 删除 |
| `d66bbbf` | MissKon | 不自动继续、占位移除、task identity guard、Keychain 重命名 |
| `11a45dd` | MissKon | 失败页 slot 移除 |
| `f183fad` | MissKon | 全部失败 UI 修复 |
| `a2f306d` | Wallhaven | uploader catch identity guard、href fallback、错误传播 |
| `736022f` | Wallhaven | HTML fallback 保序 |
| `f8a4fa5` | MissKon+Wallhaven | searchDebounce 取消、slot 按 page 序插入 |
| `a3fe562` | MissKon | 分页回归修复（newItems.isEmpty、feedErrorMessage guard） |
| `5f719f3` | MissKon | 缓存 nextPageURL nil 自动刷新 |
| `4183103` | MissKon | 分页 fallback 阈值 >=20 → >12 |
| `a46b461` | App | 完整缓存清除、中文化、设置面板整理 |
| `f84b014` | App | 每模块独立布局选项 |
| `724128b` | App | 统一布局切换 |
| `9da75cd` | Shell | +/- 图标互换 |
| `8568020` | Shell | Gallery/MissKon 独立保存/信息按钮 |
| `542424c` | MissKon+Gallery | 详情页发现 + 收藏下一张按钮 |
| `ab0456b` | MissKon+Wallhaven | 同步缓存命中封面显示 |
| `5af678f` | MissKon | 512px 缓存回退查询 |
| `beaa438` | App+Shell | Inspector 居中+换行、分享弹窗位置 |
| `210ae2f` | Shared | 分享弹窗 rect .zero + maxY |

---

## 三、模块状态

| 模块 | 分页 | 详情 | 搜索 | 收藏 | 工具栏 | 设置 |
|------|------|------|------|------|--------|------|
| 4KHDGallery | ✅ | ✅ | ✅ | ✅ | ✅ save/info 独立按钮 | ✅ 统一切换 |
| MissKon | ✅ fallback >12 | ✅ 渐进式 | ✅ debounce | ✅ | ✅ 与 Gallery 对齐 | ✅ 统一切换 |
| Wallhaven | ✅ token-guard | ✅ 单图 | ✅ force retry | ✅ | ✅ 独立按钮 | ✅ 统一切换 |
| LocalLibrary | ✅ | ✅ | — | — | ✅ | ✅ 统一切换 |

---

## 四、构建验证

所有提交均通过:
```bash
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'
```
零 error，零 warning，零 SwiftUI 命中。
