# Swift 6 严格并发（5.0）

## 模型

```text
View (@MainActor)
  → ObservableStore.dispatch
  → await Store actor.dispatch
  → Reducer (nonisolated) → Effect
  → Store runs Effect (@Sendable work)
  → follow-up Action → reduce again
  → MainActor hop updates ObservableStore.state
```

## 约束

- `State: Sendable`、`Action: Sendable`
- `Reducer` / `Effect` / `DependencyContext` 均 `Sendable`
- 禁止把 UIKit/SwiftUI 类型放进 Action 关联值

## 相对 4.x

4.x 用「整条状态管线 `@MainActor`」换取编译通过。5.0 改为三角架构，见 [ADR_TRIANGULAR_ARCHITECTURE.md](./ADR_TRIANGULAR_ARCHITECTURE.md)。
