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
- **`@MainActor` 隔离的依赖不进工厂参数** —— 工厂闭包与 `Effect` 闭包都是 `@Sendable`，
  捕获 `@MainActor` 状态会直接编译失败。需要主线程的依赖请停在 View 层。

与 4.x「整条管线 `@MainActor` Reducer」不同：5.0 让领域保持可测的纯函数，UI 隔离停在 Store。详见 [ADR_AUDITED_MIDDLEWARE_EFFECT.md](./ADR_AUDITED_MIDDLEWARE_EFFECT.md)。

`Sendable` 这条约束在使用 DI 容器时会更硬：容器的注册闭包同样是 `@Sendable`，
且隔离从闭包上下文推断 —— 注册 `@MainActor` 类型会编译失败。详见
[DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md) 与
[DEFAULT_ACTOR_ISOLATION_AND_REDUX.md](./DEFAULT_ACTOR_ISOLATION_AND_REDUX.md)。
