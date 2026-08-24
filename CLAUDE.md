# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

TGReduxKit is a lightweight Redux state management framework for SwiftUI (iOS 17+), using `@Observable` for reactive updates. It positions itself between raw SwiftUI state and The Composable Architecture (TCA) — more disciplined than bare SwiftUI, lighter than TCA.

## Build & Test Commands

```bash
# Build the package
swift build

# Run all tests
swift test

# Run a single test
swift test --filter TGReduxKitTests

# Run tests for the Demo app (from repo root)
swift test --filter TGReduxKitDemoTests

# Build documentation (DocC)
swift package generate-documentation --target TGReduxKit

# SwiftLint
swiftlint
```

## Architecture

**Data flow**: `View → dispatch(Action) → Middleware pipeline (onion model) → Reducer (pure, inout State) → @Observable notifies SwiftUI`

**6 core types in `<400 lines of Core layer**:

- `Store<State, Action>` — `@MainActor @Observable` class. Single source of truth. Holds `state`, runs middleware pipeline via `reversed().reduce()` onion composition, notifies scoped stores.
- `ScopedStore<State, Action>` — Feature-level sub-store. Projects root state via `KeyPath`, maps child actions to parent via closure. Supports recursive nesting. Receives cascade refresh after each root dispatch.
- `Reducer<State, Action>` — `(inout State, Action) -> Void`. Pure function, no side effects.
- `Middleware<State, Action>` — `@MainActor (Store, Action, @escaping Dispatch) -> Void`. Synchronous signature. Side effects (API calls, etc.) run async inside via `Task` or `store.runTask(id:)`. Pattern: `next(action)` first, then async work.
- `Dispatch<Action>` — `@MainActor (Action) -> Void`.
- `CancellationID` — `Hashable, Sendable, ExpressibleByStringLiteral`. Lightweight task identity for `runTask(id:)`.

**Key design decisions**:
- All state read/write converges on `@MainActor` — no locks needed
- Middleware uses onion model: `middlewares.reversed().reduce(initialDispatch)`
- `runTask(id:)` auto-cancels previous task with same ID (solves race conditions)
- Token mechanism in `ManagedTask` prevents cleanup misattribution
- DI is external — inject dependencies through middleware factory functions, never into Store

**Module layout**:
- `Core/` — Store, ScopedStore, Reducer, Middleware, CancellationID, DebugMiddleware
- `SwiftUI/` — StoreType, Store.binding (state→Binding bridge), StoreProvider (.provideStore environment injection)
- `Debug/` / `Testing/` — Time travel recorder, TestStore
- `Examples/TGReduxKitDemo/` — Full demo with catalog/cart/feature-flags, scoped stores, deep links（导航依赖独立包 `TGNavigationStack`）

**Related package**: Navigation (`TGRoute` / `NavigationState` / `NavigationAction` / `navigationReducer` / `TGNavigationStack`) lives in sibling repo `https://github.com/tangzzz-fan/TGNavigationStack` — not part of this package.

**State isolation pattern**: Root `ShoppingState` contains `CatalogState`, `CartState`, `FeatureFlagsState`. Each feature gets a `ScopedStore` via `store.scope(state: \.catalog, action: ShoppingAction.catalog)`. Feature flag SDK stays in infrastructure layer — only derived presentation state reaches business Views.

## Versioning & Changelog

- Follows [Semantic Versioning](https://semver.org/) and [Keep a Changelog](https://keepachangelog.com/)
- Current version: 4.0.0
- CHANGELOG.md has `[Unreleased]` section at top for pending changes
- Release workflow: move Unreleased content to a new version section → bump version → commit → git tag

## Minimum Requirements

- Swift 6.0 (tools version)
- iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0
- Zero external dependencies
