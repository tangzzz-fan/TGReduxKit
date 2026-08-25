# ADR: Triangular Architecture (TGReduxKit 5.0)

## Status

Accepted — implementation branch `review/0825-union`.

## Context

TGReduxKit 4.x bound `Reducer` / `Middleware` to `@MainActor` so module-level constants compiled under Swift 6. That leaked runtime isolation into domain types and forced Demo workarounds (`nonisolated`, separate domain packages).

Reviews `0825_reviews_01.md` / `0825_reviews_02.md` and the greenfield blueprint converge on one design.

## Decision

Adopt the triangular architecture:

1. **Domain (TGReduxKitCore)** — nonisolated `State` / `Action` / `Reducer` / `Effect` / `DependencyContext`
2. **Runtime (TGReduxKitRuntime)** — `actor Store` owns state mutation and Effect scheduling (not hard-coded `@MainActor`)
3. **UI (TGReduxKitUI)** — `@MainActor @Observable` projection (`ObservableStore`) for SwiftUI
4. **Testing (TGReduxKitTesting)** — `TestStore` with sync reduce + Effect capture

### Observation

Swift `@Observable` targets classes, not actors. Runtime `Store` remains an `actor`. UI observes via `ObservableStore`, which hops to MainActor after each successful reduce snapshot.

### Effects

Reducers return `Effect<Action>` (Elm/TCA style). Onion `Middleware` is not the primary path in 5.0.

### Package products

Same package name `TGReduxKit`, multiple products. Optional umbrella target re-exports Core+Runtime+UI for `import TGReduxKit`.

## Consequences

- Breaking 5.0.0 API; see `MIGRATION_4_TO_5.md`
- Apps no longer need `nonisolated` on domain models when Core has no MainActor default
- Demo depends on new products; example-side `Shopping` package remains local to the demo
