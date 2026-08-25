# Default Actor Isolation（5.0）

在 **TGReduxKit 5.0 三角架构**下，业务领域模型**不需要**再写 `nonisolated`。

## 为什么

| 层 | 隔离 | 结果 |
|----|------|------|
| `TGReduxKitCore` | 无 MainActor 默认 | `Reducer` / `State` / `Action` / `Effect` / `DependencyKey` 天然非隔离 |
| `TGReduxKitRuntime` | `actor Store` | 状态写入串行，不硬绑 MainActor |
| `TGReduxKitUI` | `@MainActor ObservableStore` | 仅 UI 投影在主线程 |
| App（可默认 MainActor） | View / ObservableStore | 领域代码来自独立非 MainActor 模块 |

## Demo 推荐拆分

- **一个**本地 SPM 产品 `Shopping`：模型 + Reducer + Effect + `DependencyKey`（无 MainActor 默认）
- App：仅 UI + `ObservableStore`

业务依赖走统一的 `DependencyContext`（`DependencyKey` + `withDependencies`），不要另建 `*Dependencies` 协议袋，也不必再拆 Domain/Feature 两个 target。

不要把 Effect/Reducer 放进默认 MainActor 的 App target，再靠 `nonisolated` 补丁。

## 历史（4.x）

4.x 曾将 `Reducer` 绑到 `@MainActor`，迫使 Demo 用 `nonisolated` 或拆 domain 模块。5.0 用 Core/Runtime/UI 拆分从根上消除该压力。详见 [ADR_TRIANGULAR_ARCHITECTURE.md](./ADR_TRIANGULAR_ARCHITECTURE.md) 与 [MIGRATION_4_TO_5.md](./MIGRATION_4_TO_5.md)。
