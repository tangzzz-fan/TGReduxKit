# Default Actor Isolation 与 Redux 领域模型

本文记录 Demo App 在 Xcode 26 / Swift 6.2「默认 MainActor」下与 TGReduxKit 集成时踩到的并发问题：现象、本质、正确解法，以及可复用的启示。

相关文档：[STRICT_CONCURRENCY_MIGRATION.md](./STRICT_CONCURRENCY_MIGRATION.md)（库层把 `Reducer` 收口到 `@MainActor`）。

## 问题

接入 Demo（`Examples/TGReduxKitDemo`）在严格并发下出现两类编译失败，表面像「导航库 / Redux 库坏了」：

1. **枚举模式匹配失败**  
   `case .push(let route)` 报 `'let' binding pattern cannot appear in an expression`，或  
   `enum case 'push' is not available due to missing import of defining module 'TGNavigationStack'`。

2. **Actor 服务无法同步构造领域值**  
   `DemoFeatureFlagService`（`actor`）里创建 `FeatureFlagSnapshot` 时，编译器要求 `await`：  
   认为 Snapshot 的初始化在 MainActor 上。

临时「整 target 改成 `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`」能消掉第 2 类错误，但会立刻撞上第 3 类：

3. **模块级 reducer 组合报错**  
   `combineReducers` / `pullback` 是 TGReduxKit 的 `@MainActor` API，在 nonisolated 全局上下文中不能直接调用。

给每个领域类型手写 `nonisolated` 能过编译，但在真实项目里不优雅：隔离噪声散落在模型层，且一漏标就复发。

## 本质

这不是单一 bug，而是 **三层边界叠在一起**：

```text
┌─────────────────────────────────────────────────────────────┐
│  App target: SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor     │
│  （Xcode 26 模板默认：未标注声明 → 推断为 @MainActor）        │
├─────────────────────────────────────────────────────────────┤
│  TGReduxKit: Store / Middleware / Reducer @MainActor       │
│  （有意契约：状态管线收敛主线程）                              │
├─────────────────────────────────────────────────────────────┤
│  TGNavigationStack: navigationReducer 非隔离纯函数          │
│  NavigationAction / TGRoute 为跨模块 Sendable 值类型         │
└─────────────────────────────────────────────────────────────┘
```

| 现象 | 真正根因 | 责任归属 |
|------|----------|----------|
| `.push` 模式匹配失败 | 开启了 `Member Import Visibility`，使用他模块枚举 case 必须 `import` 定义模块 | **App / 编译设置**，不是导航库缺陷 |
| Actor 里构造 Snapshot 要 `await` | 默认 MainActor 把未标注的领域类型推断成 MainActor；`actor` 不能同步碰它们 | **领域模型与 UI 默认隔离挤在同一 target** |
| 关掉默认 MainActor 后又炸 `combineReducers` | TGReduxKit 公开把 reducer 组合绑在 `@MainActor` | **库设计选择**（与文档一致），不是疏漏 |
| 到处标 `nonisolated` 很丑 | 用成员级注解修补 **模块级错误默认** | 说明应换边界，而不是加注解 |

核心矛盾一句话：

> UI App 的「默认 MainActor」很好；Redux 的 State / Action / Snapshot 是 **跨隔离域传递的纯值**，不该和 UI 共用同一个默认隔离模块。

第三方库角色清晰：

- **TGReduxKit**：状态读写与 dispatch 在 MainActor —— 正确且应遵守。
- **TGNavigationStack**：纯 `navigationReducer` 不绑 MainActor —— 正确收窄。
- **冲突发生在 Demo 结构**：领域模型、actor 服务、SwiftUI 同 target，却继承了 UI 的 MainActor 默认。

## 解决方案（最佳实践）

### 原则

用 **模块边界** 表达隔离，而不是在每个类型上写 `nonisolated`：

```text
ShoppingDomain（无 MainActor 默认）
  State / Action / Model / Snapshot / 纯函数 / actor 服务
        ↑ import
TGReduxKitDemo App（MainActor 默认）
  View / Store 装配 / Reducer / Middleware
        ↑
TGReduxKit（Store 管线 @MainActor）
TGNavigationStack（navigationReducer 非隔离）
```

### 1. 推荐：拆 Domain 模块（Demo 已采用）

把领域放到独立 Swift Package，**不设置** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（保持 SPM 默认非隔离）：

```text
Examples/TGReduxKitDemo/ShoppingDomain/
  Package.swift          # 依赖 TGNavigationStack；无 defaultIsolation(MainActor)
  Sources/ShoppingDomain/
    Models.swift
    StateAndActions.swift
    Services.swift
```

App target 继续 MainActor 默认，只依赖 `ShoppingDomain` 产品。效果：

- 领域类型 **零** `nonisolated` 注解，天然可被 `actor` / `Task` 使用；
- UI / `combineReducers` 仍享受 MainActor 默认与 TGReduxKit 契约；
- 隔离策略写在 Package / target 设置里，而不是散落在每个 `struct` 上。

这是 SE-0466 在「UI 默认 MainActor」工程里的正确用法：默认隔离按 **target** 选择，而不是在巨型 App target 里逐类型 opt-out。

### 2. 保留 App 的 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`

不要为了过编译把 Demo 改成 `nonisolated`。那会丢掉 SwiftUI 模板收益，并强迫 reducer 全局常量再手补 `@MainActor`。

### 3. 同模块时的权宜：`nonisolated` 整型 opt-out

若暂时不能拆模块，应对 **整个类型** 标 `nonisolated`，而不是只标 `init`：

```swift
nonisolated public struct FeatureFlagSnapshot: Equatable, Sendable { ... }
```

这能过编译，但一旦领域类型变多，注解噪声会提示你：该拆 Domain 了。

### 4. 使用他模块枚举时显式 `import`

在开启 Member Import Visibility 时：

```swift
import TGNavigationStack  // 才能匹配 NavigationAction.push 等 case
import ShoppingDomain
```

### 不推荐的做法

| 做法 | 为什么不推荐 |
|------|----------------|
| Target 默认改成 `nonisolated` | 用错了 SE-0466 的旋钮；和 TGReduxKit 的 MainActor 管线打架 |
| 给每个领域模型手写 `nonisolated` | 能工作，但不优雅；用成员注解修补模块边界 |
| 只给个别 `init` / `static` 补 `nonisolated` | 类型隔离域仍含糊，易复发 |
| 要求 TGReduxKit 去掉 Reducer 的 `@MainActor` | 把库契约扯进 App 结构问题；方向相反 |
| 要求 TGNavigationStack 把 reducer 绑回 MainActor | 与「纯逻辑隔离尽量窄」相反 |

## 启示

1. **严格并发首先是边界问题。**  
   Store 管线可以在主线程；跨服务传递的值类型必须能离开主线程——最好用 **独立 domain target** 表达，而不是注解轰炸。

2. **到处需要 `nonisolated`，说明默认隔离选错了模块。**  
   SE-0466：UI target 默认 MainActor；领域 / 数据 target 保持非隔离。注解是逃生舱，不是主方案。

3. **诊断要拆层，避免误伤库。**  
   缺 `import`、领域与 UI 同模块、库的 `@MainActor` API，根因不同。

4. **两个库的策略可以共存。**  
   TGReduxKit：状态流 MainActor。TGNavigationStack：reducer 非隔离。MainActor reducer 调用非隔离纯函数合法且推荐。

5. **接入检查清单**

   - [ ] App 保持 MainActor 默认（UI target）
   - [ ] State / Action / Model 放在 **无 MainActor 默认** 的 Domain 模块（优先），或整型 `nonisolated`（权宜）
   - [ ] 使用他模块枚举 case 的文件已 `import` 定义模块
   - [ ] 副作用服务在 Domain / Infrastructure，经 `dispatch` 回到 MainActor Store
   - [ ] 不要为了过编译关闭整 App 默认隔离，或削弱库的 MainActor 契约

## 参考

- [SE-0466: Control default actor isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)
- [SE-0449: `nonisolated` for global-actor cutoff](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0449-nonisolated-for-global-actor-cutoff.md)
- 本仓库 [STRICT_CONCURRENCY_MIGRATION.md](./STRICT_CONCURRENCY_MIGRATION.md)
- Demo：`Examples/TGReduxKitDemo/ShoppingDomain` + App target reducers / views
