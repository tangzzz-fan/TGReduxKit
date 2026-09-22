# Default Actor Isolation（5.0）

Xcode / 部分 App target 可能默认 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。领域模型若与 UI 同 target，会被迫到处标 `nonisolated`。

## 推荐边界

| 层 | 隔离 | 内容 |
|----|------|------|
| SPM Domain（如 Demo `Shopping`） | **无** MainActor 默认 | `State` / `Action` / 纯 Reducer / 服务协议 |
| `TGReduxKitRuntime` | `@MainActor` `Store` | 调度、`managedTasks` |
| App / Views | 可默认 MainActor | View、Composition Root 组装 Store |

不要在领域类型上喷 `nonisolated` 补丁；把领域代码放进独立 SPM target。

业务依赖用 Middleware 工厂注入（[DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md)），不要塞进 Store。

## 为什么这条边界是硬的，不只是风格问题

除了"避免到处喷 `nonisolated`"，这条边界还有一条**功能性**后果：

**在默认 MainActor 的 target 内定义的类型会隐式 `@MainActor` 隔离，因此无法直接注册进 DI 容器。**
Factory 的注册闭包是 `@Sendable` 且隔离从闭包所在上下文推断，注册 `@MainActor` 类型会直接编译失败。

所以 Demo 的 Factory 示例能编译，**不是因为它配置对了，而是因为它的服务住在 `Shopping` 这个没有 MainActor 默认的 target 里**。
把 `LiveProductSearchService` 移进 app target，Factory 注册立刻编译失败。

完整实测矩阵与修法（唯一有效的是**注解闭包** `self { @MainActor in … }`）见
[DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md) 的「⚠️ 可注册域 ⊆ `Sendable`」一节。

## Demo 现状

| Target | `SWIFT_VERSION` | `SWIFT_DEFAULT_ACTOR_ISOLATION` |
|--------|-----------------|--------------------------------|
| `TGReduxKitDemo`（App） | 6.0 | `MainActor` |
| `TGReduxKitDemoTests` | 6.0 | 跟随 App target 设置 |
| `TGReduxKitDemoUITests` | 6.0 | 跟随 App target 设置 |
| `Shopping`（SPM Domain） | 6（`swiftLanguageModes: [.v6]`） | 无 |
| `TGReduxKit`（SPM） | 6 | 无 |

App、测试 target 与两个 SPM 包现在跑在同一套并发检查下（`project.pbxproj` 里 6 处
`SWIFT_VERSION` 全为 `6.0`，无残留 `5.0`）。

> 测试 target 提 6 之所以零成本，是因为**所有被注册 / 被捕获的依赖都是 `Sendable`**
> （`ProductSearching` / `FeatureFlagFetching` 是 `Sendable` 协议，`now` 是 `@Sendable () -> Date`）。
> 若将来引入 `@MainActor` 服务，见上文「为什么这条边界是硬的」。
