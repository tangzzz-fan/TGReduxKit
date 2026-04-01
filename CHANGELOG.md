# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-04-02

### Changed
- **Release**
  - Promoted TGReduxKit to `1.0.0` to reflect a stabilized public API centered on `@MainActor Store`, `ScopedStore`, lightweight task cancellation, and documented integration patterns.

### Added
- **Core / Scope**
  - Added `ScopedStore<State, Action>` for feature-level state/action projection.
  - Added nested `scope(state:action:)` support from both `Store` and `ScopedStore`.
- **Core / Cancellation**
  - Added `CancellationID` as a lightweight task identity.
  - Added `runTask(id:priority:operation:)`, `cancelTask(id:)`, and `cancelAllTasks()` on `Store`.
- **Core / Debug**
  - Added `actionLoggingMiddleware()` for action tracing.
  - Added `stateDiffMiddleware()` for before/after state inspection.
- **SwiftUI**
  - Added `provideStore(_:)` overload for `ScopedStore`.
  - Added `ScopedStore.binding(get:send:)` to keep feature views on the same binding API.
- **Tests**
  - Added coverage for scoped store synchronization, nested scopes, task cancellation, and debug middleware.

### Changed
- **Core / Concurrency**
  - Moved `Store` to `@MainActor` to unify state reads, writes, and dispatch on the main thread.
  - Moved `Dispatch` and `Middleware` execution semantics to `@MainActor`.
  - Removed the previous `NSLock`-based mixed concurrency path in favor of a single actor-isolated model.
- **Core / State Flow**
  - Store dispatch now notifies scoped stores after reducer execution so feature stores remain synchronized with root state.

### Documentation
- **README**
  - Updated the public guide to match the actual reducer and middleware model.
  - Added scoped store, cancellation, and debug middleware examples.
  - Added a dependency injection integration example that keeps DI containers outside the store boundary.
  - Added a feature flag integration example that maps remote flag values into explicit state and actions.
- **ARCHITECTURE**
  - Rewrote the architecture description around `@MainActor Store`, `ScopedStore`, and lightweight cancellation.

### Demo
- **TGReduxKitDemo**
  - Updated the demo app to use `ScopedStore` for catalog and cart features.
  - Added a debounced product search flow implemented with `store.runTask(id:)`.
  - Added a dependency-driven middleware builder example through `ShoppingDependencies`.
  - Switched the demo logging example to the built-in `actionLoggingMiddleware()`.

## [0.0.2] - 2026-01-14

### Changed
- Moved `TGReduxKitDemo` into `Examples/` directory for better project structure.
- Updated demo project dependencies to reference the local package correctly.
- Removed obsolete `CounterAppExample.swift`.

## [0.0.1] - 2026-01-11

### Added
- **Core**: Initial implementation of `Store`, `Middleware`, and `Reducer`.
- **SwiftUI**: Added `StoreProvider` (via `.provideStore`) and `Store.binding` helper.
- **Concurrency**: Full support for Swift 6 strict concurrency checks (`Sendable` conformance).
- **Documentation**:
  - Comprehensive API documentation (DocC).
  - Architecture diagram and usage guide in `README.md`.
  - Advanced usage examples (Async Middleware, Modular Reducers).
- **Examples**: Added `CounterAppExample` in `Examples/` directory.
- **CI/Quality**: Added `.swiftlint.yml` configuration.
