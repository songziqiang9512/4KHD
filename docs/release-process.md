# 4KHD 发布流程

本项目使用 `main` 上的已提交版本号和受保护的 GitHub Actions `Build Prerelease` 流程发布。工作流创建不可变 `build-{version}` prerelease，并更新 `update-feed/appcast.xml`。

## 发布前

1. `git fetch --prune --tags origin`，确认当前分支、`origin/main`、最高 `build-*` 标签和工作树归属。
2. 用 `script/resolve_version.sh --next` 计算下一个版本；用 `script/update_version.sh --next` 同时更新 Debug/Release 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，版本必须先提交到源码。
3. 同步 `README.md`、`AGENTS.md`、最新 handover、协议文档和 `docs/releases/{version}.md`。发布工作流优先直接使用对应版本的发布说明；缺失时才回退到提交标题。
4. 执行全量 XCTest、Debug/Release 构建、生产代码 0 SwiftUI 扫描、`git diff --check` 和 workflow/YAML 基础校验。

## 推送与触发

1. 只暂存本批明确文件，核对 staged diff 后提交；不要使用 `git add -A` 混入并行工作。
2. 已手动提交版本号时，用 `SKIP_VERSION_PREPUSH=1 git push origin main`，避免 pre-push hook 再次准备版本。
3. 确认 `origin/main` 指向已验证提交后触发：

```bash
gh workflow run build-prerelease.yml \
  --repo songziqiang9512/4KHD \
  --ref main \
  -f version=1.8.9 \
  -f confirm_release=true
```

实际版本必须替换为本次已提交版本。`release` environment 只允许 `main`，并要求仓库所有者审批；不要提前创建标签或 release。

## 工作流职责

受保护工作流负责 XCTest、Developer ID 签名、App/DMG 公证与 staple、Gatekeeper 和 entitlement 验证、dSYM、SHA-256、Sparkle EdDSA appcast、不可变 prerelease 及 update-feed 更新。

通常应在完成后核对 release、tag、assets 与 appcast；如果用户明确要求在正确推送和触发后自行观察，可以在报告 workflow run 后移交，不把未观察到的完成状态写成已验证。
