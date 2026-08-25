# ADR: Audited Middleware + Effect Architecture

## Status

Accepted on `feat/audited-middleware-effect-architecture`.

## Decision

| Layer | Role |
|-------|------|
| **TGReduxKitCore** | `State` / `Action` / pure `Reducer` → `Void` / declarative `Effect` |
| **TGReduxKitRuntime** | `@MainActor` `Store` + Middleware → Effect → `runTask` / `ScopedStore` |
| **TGReduxKitUI** | `provideStore` / `binding` |
| **TGReduxKitDebug** | logging / state-diff / error-reporting middleware |

### Fixes from audit

- `Effect.Operation.merge` is `indirect` for nested composition
- `managedTasks` stores `Task<Void, Never>` directly (no UUID token wrapper)
- `ScopedStore` syncs via `stateProvider()` in `init`
- Tests use **Swift Testing** (`import Testing`), not XCTest

### Dependency injection

No DI container. See `Docs/DEPENDENCY_INJECTION.md` and Demo `ShoppingDependencies` + middleware factories.

### Note

SwiftUI’s `@State` conflicts with protocol `State` — qualify as `@SwiftUI.State` at call sites.
