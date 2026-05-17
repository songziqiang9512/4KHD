# 4KHD 顶层开发规范

本文件是 4KHD 项目的顶层开发规范。

适用范围：

- 整个仓库
- 所有后续新增模块
- 所有结构调整、重构、功能开发、Bug 修复

## 1. 总体原则

4KHD 的长期方向不是继续围绕单一功能堆代码，而是建设一个可持续发展的桌面工作区应用底壳。

因此后续所有开发默认遵守以下原则：

1. 底壳独立。
2. 模块独立。
3. 公共能力独立。
4. 删除任意模块，不应影响其他模块运行。
5. 新增模块，不应要求重写底壳。

## 2. 架构规范来源

本项目的模块化底壳与目录规划，以以下文档作为正式规范来源：

- [docs/architecture-module-shell-plan.md](/Users/songziqiang/Documents/Development/4KHD/docs/architecture-module-shell-plan.md)

后续涉及以下事项时，必须优先遵守该文档中的边界定义与迁移方向：

1. 目录调整
2. 新模块接入
3. 共享能力抽取
4. Shell 改造
5. Store 命名与职责划分
6. Toolbar / Sidebar / Workspace 路由设计

如果临时实现与该规划冲突，应优先修正实现，不应继续扩大冲突面。

## 3. 当前默认模块命名

当前项目中的在线模块命名为：

- `4KHDGallery`

本地模块命名为：

- `LocalLibrary`

收藏能力按独立横切模块对待：

- `Favorites`

## 4. 代码组织约束

后续代码组织默认朝以下结构收敛：

```text
4KHD/
  App/
  Shell/
  Shared/
  Modules/
```

要求：

1. `App` 只放应用入口与场景组装。
2. `Shell` 只放工作区底壳、模块路由、共享布局容器。
3. `Shared` 只放跨模块可复用能力。
4. `Modules` 只放业务模块实现。

禁止继续扩大以下混合式结构：

1. 把新模块逻辑直接堆进 `WorkspaceShell`
2. 把在线模块继续分散进 `Core / UI / Web`
3. 把本地模块平台细节和壳层能力写死在同一文件里

当前代码现状：

1. 顶层目录已完成收敛到 `App / Shell / Shared / Modules`。
2. `App` 已承担场景组装职责，模块实例与 `WorkspaceModuleRegistry` 由装配层创建。
3. `Shell` 已通过 `WorkspaceModuleRegistry` 渲染 sidebar / content / detail，不再直接创建具体模块 store。
4. App 生命周期、主窗口、三栏工作区、source list、toolbar、中栏列表/网格和详情区均已迁移到 AppKit。
5. `Shared` 已承载通用图片加载缓存、cookie 桥接、详情区状态、filmstrip 可见性和平台桥接等公共能力。
6. `Favorites` 已从直接持有 `GalleryItem` 的实现，收敛为只持有自己的收藏记录；业务模块自行桥接到各自模型。
7. 生产代码当前应保持 `0 SwiftUI`：不得重新引入 `import SwiftUI`、`NSHostingController`、`NSViewRepresentable`、`AnyView` 或 SwiftUI 状态机制。

当前仍未完全完成的事项：

1. `WorkspaceShell.swift` 仍偏大，侧栏、split layout 和沉浸相关实现还在同文件内。
2. Toolbar 仍集中在 `4KHDApp.swift` 内，后续若继续扩展应拆出壳层 toolbar host，而不是把模块按钮继续堆进入口文件。
3. 中栏 AppKit 列表/网格体验已迁移完成，但在线模块和本地模块仍各自维护列表/网格实现；后续若统一，应优先统一交互和布局行为，而不是强行合并控件实现。
4. 详情区开合、工具栏控制和中栏自动避让已有第一版壳层状态，但仍需要继续做手动验收和细节收敛。

## 5. 模块开发约束

每个业务模块都应尽量满足：

1. 有清晰的模块边界。
2. 有自己的 `Domain / State / Services / UI` 分层。
3. 只能依赖 `Shared` 和系统框架。
4. 不直接依赖其他模块的内部实现。
5. 通过模块注册或模块接入面挂入底壳。

如果新增功能必须直接修改多个现有模块内部实现，先判断是否应该下沉到 `Shared` 或上提到 `Shell`。

## 6. Shared 抽取约束

只有满足以下条件的能力，才应进入 `Shared`：

1. 至少两个模块会使用。
2. 不带强业务语义。
3. 放进共享层后不会反向污染模块边界。

不满足条件时，不要为了“看起来通用”强抽。

## 7. 变更优先级

涉及结构演进时，默认优先级如下：

1. 先保持底壳稳定。
2. 再保证模块可独立维护。
3. 再抽共享能力。
4. 最后才考虑更大规模重构。

## 8. 文档维护要求

如果未来结构方向发生实质变化，必须同步更新：

1. `AGENTS.md`
2. `docs/architecture-module-shell-plan.md`

不要让顶层规范与实际代码长期背离。
