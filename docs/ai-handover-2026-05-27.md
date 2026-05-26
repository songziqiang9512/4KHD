# AI Handover — 2026-05-27

给下一个开发助手恢复上下文用。更细的架构规范看 `AGENTS.md`。

## 接手顺序

1. 读 `AGENTS.md`
2. 读本文
3. 运行构建验证：

```bash
xcodebuild -project 4KHD.xcodeproj -scheme 4KHD -configuration Debug -destination 'platform=macOS' build
```

## 当前状态

| 模块 | 状态 | 注意事项 |
|------|------|----------|
| `4KHDGallery` | 稳定 | 在线模块参考实现；支持列表/网格切换保留滚动位置 |
| `MissKon` | 核心链路完整 | 已接入收藏、Inspector、详情重试、搜索高亮、磁盘列表缓存 |
| `LocalLibrary` | 稳定 | 本地图片导入、扫描、metadata 读取 |
| `Favorites` | 稳定 | 共享 `FavoritesStore`；收藏桥必须做域名校验 |

项目约束：纯 AppKit，生产代码 `0 SwiftUI`，macOS 26+，Swift 6，SPM/Nuke。

## 在线模块注意事项

- 修改 MissKon 的 Shell 集成时，先搜索 `case .missKon` 覆盖所有 switch。
- 修改任一在线模块时，以 `4KHDGallery` 的状态流和 UI 行为为参考。
- 异步请求返回后必须按请求时的 section/query 写回，不能直接读当前 UI 状态。
- 收藏桥和详情图片解析使用 exact/subdomain allowlist，不要用 `host.contains(...)`。
- 详情 HTML 截取不要用 `lowercased()` 产生的 `String.Index` 切原字符串；用 `NSString`/`NSRange` 或原字符串 case-insensitive range。
- MissKon 列表缓存路径：`~/Library/Application Support/4KHD/MissKon/feed-cache.json`，网络缓存 1 小时过期；收藏 section 始终读 `FavoritesStore`。

## 剩余任务

- 当前工程只有 `4KHD` App target，尚未配置 XCTest target；补单元测试前需要先建测试 target 和可测的纯逻辑入口。
- HTML 解析仍依赖目标站点结构，改解析器时优先保留降级路径和错误信息。

## 常用命令

```bash
# 验证 0 SwiftUI
rg "import SwiftUI|NSHosting|NSViewRepresentable|AnyView" 4KHD --glob '*.swift'

# 查 MissKon 集成点
rg "case \.missKon" 4KHD/Shell 4KHD/App --glob '*.swift'

# 查 Gallery 参考实现
rg "case \.fourKHDGallery" 4KHD/Shell 4KHD/App --glob '*.swift'

# 清理 DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/4KHD-*
```
