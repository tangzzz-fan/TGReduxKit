# Swift 6 严格并发（5.0）

```text
View (MainActor)
  → Store.dispatch (@MainActor)
  → Middleware → Effect
  → Reducer (nonisolated / @Sendable，由 Store 在 MainActor 上调用)
  → Store 运行 @Sendable Effect 闭包
  → follow-up Action 回到 MainActor dispatch
```

要点：

- `State` / `Action`：`Sendable`（协议约束）
- `Reducer`：`@Sendable (inout State, Action) -> Void`，无 actor 绑定
- `Effect` 操作闭包：`@Sendable`
- 依赖：`Sendable` 或 actor，由工厂捕获进 Middleware / Effect

与 4.x「整条管线 `@MainActor` Reducer」不同：5.0 让领域保持可测的纯函数，UI 隔离停在 Store。详见 [ADR_AUDITED_MIDDLEWARE_EFFECT.md](./ADR_AUDITED_MIDDLEWARE_EFFECT.md)。
