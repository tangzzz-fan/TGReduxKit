# ADR: Audited Middleware + Effect Architecture

## Status

**Accepted** — TGReduxKit **5.0.0** 现行架构。

## Decision

| Layer | Role |
|-------|------|
| **TGReduxKitCore** | `State` / `Action` / pure `Reducer` → `Void` / declarative `Effect` / `CancellationID` |
| **TGReduxKitRuntime** | `@MainActor @Observable` `Store`；Middleware → `Effect`；`ScopedStore` / `StoreType` |
| **TGReduxKitUI** | `provideStore` / `binding` |
| **TGReduxKitDebug** | logging / state-diff / error-reporting middleware |
| **TGReduxKitTesting** | 纯 Reducer 用 `TestStore` |

### Invariants

- Reducer **永不**返回 Effect、**永不**持有业务依赖  
- Middleware 工厂注入依赖；闭包捕获后返回 `Effect`  
- Store 解释 `Effect`（`task` / `cancel` / `merge`），经 `managedTasks` 管理取消  
- `Effect.Operation.merge` 为 `indirect`，支持嵌套  
- UI 侧协议名冲突时使用 `@SwiftUI.State`

### Dependency injection

无 DI 容器。见 [DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md) 与 Demo `ShoppingDependencies`。

### Supersedes

早期 5.x 草案（`actor Store` + `ObservableStore`、Reducer 返回 Effect、`DependencyContext`）均已废弃，不再保留独立 ADR。
