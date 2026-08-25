# CLAUDE.md

Guidance for agents working in this repository.

## Project Overview

TGReduxKit 5.x — lightweight Redux for SwiftUI with a **triangular architecture**:

1. **Domain (Core)** — nonisolated `Reducer` / `Effect` / `DependencyContext`
2. **Runtime** — `actor Store` owns state + effect scheduling
3. **UI** — `@MainActor @Observable` `ObservableStore` projection

## Build & Test

```bash
swift build
swift test
swift test --filter CoreReducerTests
# Demo
xcodebuild -project Examples/TGReduxKitDemo/TGReduxKitDemo.xcodeproj -scheme TGReduxKitDemo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Module layout

- `Sources/TGReduxKitCore` — protocols, CancellationID, DependencyContext, Effect, Reducer, combine/pullback
- `Sources/TGReduxKitRuntime` — `actor Store`
- `Sources/TGReduxKitUI` — `ObservableStore`, `provideStore`
- `Sources/TGReduxKitTesting` — `TestStore`
- `Sources/TGReduxKit` — `@_exported` umbrella
- `Examples/TGReduxKitDemo` — shopping demo (+ local `Shopping` package)
- Navigation: sibling `TGNavigationStack`

## Design rules

- Never put `@MainActor` on domain reducers
- Side effects return `Effect`; do not reintroduce onion Middleware as the primary path
- UI observes via `ObservableStore`, not the actor directly
- Keep Core free of SwiftUI

## Versioning

- SemVer + Keep a Changelog
- Current line: **5.0.0 (Unreleased on branch `review/0825-union`)**
- See `Docs/MIGRATION_4_TO_5.md`
