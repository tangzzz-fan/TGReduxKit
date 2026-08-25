# Default Actor Isolation（5.0）

在 **TGReduxKit 5.0 三角架构**下，业务领域模型**不需要**再写 `nonisolated`。

## 为什么

| 层 | 隔离 | 结果 |
|----|------|------|
| `TGReduxKitCore` | 无 MainActor 默认 | `Reducer` / `State` / `Action` / `Effect` 天然非隔离 |
| `TGReduxKitRuntime` | `actor Store` | 状态写入串行，不硬绑 MainActor |
| `TGReduxKitUI` | `@MainActor ObservableStore` | 仅 UI 投影在主线程 |
| App（可默认 MainActor） | View / ObservableStore | 领域类型来自 Core，不会被 App 默认隔离“污染” |

框架自己扛隔离边界；不要再把领域类型塞进「默认 MainActor 的巨型 App target」却不拆模块——即便 App 默认 MainActor，只要类型定义在 Core（或独立非 MainActor domain target），也仍然安全。

## 历史（4.x）

4.x 曾将 `Reducer` 绑到 `@MainActor`，迫使 Demo 用 `nonisolated` 或拆 `ShoppingDomain`。5.0 用 Core/Runtime/UI 拆分从根上消除该压力。详见 [ADR_TRIANGULAR_ARCHITECTURE.md](./ADR_TRIANGULAR_ARCHITECTURE.md) 与 [MIGRATION_4_TO_5.md](./MIGRATION_4_TO_5.md)。
