# ADR: Industrial Compromise Architecture (TGReduxKit 5.x)

## Status

Accepted on branch `feat/industrial-compromise-mainactor-effects` — supersedes pure “actor Store + ObservableStore projection” for the SwiftUI product surface.

## Context

Counterexample review proved: a non-MainActor `actor` cannot be a SwiftUI state root. Streaming side effects need multi-value `Send`, not only `() async -> Action?`. Meanwhile, returning `Effect` from reducers remains the right Swift concurrency model versus onion Middleware.

## Decision

| Component | Decision |
|-----------|----------|
| **Store** | `@MainActor @Observable final class` — sync UI access |
| **Reducer** | `(inout State, Action) -> Effect<Action>` — **no** `DependencyContext` injection; capture `@Sendable` closures in factories |
| **Effect** | `run { send in … }` multi-value + `cancellable(id:)` / debounce / merge |
| **Middleware** | Deleted (not primary path) |
| **Domain** | Independent SPM target without MainActor default |
| **dispatch** | Returns `Task<Void, Never>?` — caller may cancel or discard |

`ObservableStore` remains a **typealias** of `Store` for migration.

`DependencyContext` / `DependencyKey` stay as an **optional app-level bag**, not wired into reduce/Store.

## Consequences

- Breaking vs early triangular actor-Store draft on `review/0825-union`
- Aligns with TCA-like Effect testing (assert effect structure via `TestStore.send`)
- SwiftUI physical constraint honored without abandoning structured concurrency

## References

- `Docs/ARCHITECTURE_COUNTEREXAMPLES.md`
- Architect response: MainActor Store + Effect stream + Task-returning dispatch
