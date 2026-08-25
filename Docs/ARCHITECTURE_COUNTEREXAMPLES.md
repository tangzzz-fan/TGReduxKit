# 架构反例验证（相对三角方案断言）

本文档对应一组可编译验证的反例，用于检验「纯 Actor Store / `@Observable` actor / Effect 返回依赖注入 / dispatch→Task / 单值 Effect / 模块隔离」等断言。  
分支：`test/architecture-counterexamples`。自动化正向证明见 `Tests/TGReduxKitTests/ArchitectureCounterexampleVerificationTests.swift`。

## 与 TGReduxKit 5.0 的关系

| 反例 | 反例要证伪的断言 | 5.0 实际做法 | 验证结论 |
|------|------------------|--------------|----------|
| 1 | Actor Store 可直接当 SwiftUI 根 | **Runtime `actor Store` + UI `ObservableStore`** | 反例成立；方案已用投影层规避 |
| 2 | actor + `@Observable` + `nonisolated state` | **不把 Store 标成 `@Observable actor`**；UI 类才 `@Observable` | 反例成立；方案未采用该组合 |
| 3 | Reducer+Effect+DI 测试必爆炸 | **TestStore 默认同步记录 Effect，不跑异步** | 反例部分成立；纯状态仍可同步测 |
| 4 | `dispatch → Task` 给调用方 | **`ObservableStore.dispatch` → `Void`（F&F）**；Task 在 Runtime 内 | 反例成立；5.0 未把 Task 抛出 |
| 5 | 单值 `() async → Action?` 表达流 | Effect 单 follow-up；流式需多次 Action / 未实现 `send` | **能力缺口属实**（已知限制） |
| 6 | 同 target MainActor 默认污染领域 | **Core / Demo `Shopping` 独立无 MainActor 默认** | 反例成立；分层编译单元是正解 |

下文「负向」片段预期**编译失败**；勿加入默认 build target。正向测试应**编译通过**并在 `swift test` 中绿色。

---

## 反例 1：非 MainActor actor 无法在 SwiftUI 同步访问

**断言**：「Store 必须是 Actor，不硬编码 MainActor」若被理解成「SwiftUI 直接绑 actor」，则不可行。

**负向（预期编译失败）**：见 [`Examples/ArchitectureCounterexamples/Negatives/Counterexample01_PlainActorInSwiftUI.swift`](../Examples/ArchitectureCounterexamples/Negatives/Counterexample01_PlainActorInSwiftUI.swift)（默认不参与编译）。

**正向**：`ObservableStore` 在 `@MainActor` 下同步读 `state`、同步 `dispatch`（内部 `Task`）。  
`dispatch` / `dispatchAndWait` 用 Runtime 返回的 snapshot 写回投影（不单靠异步 `stateHandler`），避免首帧丢更新。

---

## 反例 2：`@Observable` + actor + `nonisolated state` 观察断裂

**断言**：把 actor 标 `@Observable` 并用 `nonisolated` 暴露 state，观察会断或无法写入。

**负向**：[`…/Counterexample02_BrokenObservableActor.swift`](../Examples/ArchitectureCounterexamples/Negatives/Counterexample02_BrokenObservableActor.swift)。

**正向**：变更经 Runtime reduce → `stateHandler` → MainActor 写 `ObservableStore.state`，触发 `@Observable`。

---

## 反例 3：Reducer 返回 Effect 的测试成本

**断言**：一旦 Reducer 接 `DependencyContext` 并返回 Effect，测试必然异步爆炸。

**部分反驳**：`TestStore.send` 只同步 reduce + **记录** Effect，不 `await`；纯状态断言仍可 3 行完成。跑 Effect 是可选第二层。

**正向测试**：`counterexample03_syncTestStoreDoesNotAwaitEffects`。

---

## 反例 4：`dispatch` 返回 `Task` 的死胡同

**断言**：把 Task 句柄交给 View 调用方。

**5.0**：`ObservableStore.dispatch` 返回 `Void`；取消表在 `actor Store` 内。

**正向测试**：`counterexample04_dispatchIsFireAndForgetReturningVoid`。

---

## 反例 5：单值 Effect 无法表达流式副作用

**断言**：`run: () async → Action?` 只能产出至多一个 follow-up。

**成立**：进度 / WebSocket 流需要 TCA 式 `Effect.run { send in }` 或多次 Action 编排；5.0 首切未提供 `send` 回调。

**正向测试**：单次 `.run` 只产生一个 follow-up；多步需 reducer 链或 `.merge`。

---

## 反例 6：默认隔离必须靠独立编译单元

**断言**：同 App target（MainActor 默认）定义领域类型会污染隔离。

**5.0**：`TGReduxKitCore` 与 Demo `Shopping` 为独立产品，无 MainActor 默认。

**正向测试**：在非 MainActor 的测试/`actor` 上下文中构造 Core 状态与调用 `Reducer`（无 await 值类型）。

---

## 如何跑

```bash
swift test --filter ArchitectureCounterexampleVerificationTests
# 负向片段：打开 Negatives/*.swift 的说明，复制到临时 target 或 Playground 验证编译错误
```
