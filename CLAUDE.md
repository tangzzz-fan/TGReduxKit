# CLAUDE.md

Guidance for agents working in this repository.

## Project Overview

TGReduxKit 5.x — lightweight Redux for SwiftUI (**industrial compromise**):

1. **Domain (Core)** — nonisolated `Reducer` / streaming `Effect` / optional `DependencyContext`
2. **Runtime** — `@MainActor @Observable` `Store` owns state + effect scheduling
3. **UI** — bindings + `provideStore` (`ObservableStore` is a typealias of `Store`)

## Build & Test

```bash
swift build
swift test
swift test --filter ArchitectureCounterexampleVerificationTests
# Demo
xcodebuild -project Examples/TGReduxKitDemo/TGReduxKitDemo.xcodeproj -scheme TGReduxKitDemo -destination 'platform=iOS Simulator,name=iPhone 17' build
```

## Module layout

- `Sources/TGReduxKitCore` — protocols, CancellationID, Effect (`Send`), Reducer, combine/pullback
- `Sources/TGReduxKitRuntime` — `@MainActor` `Store`
- `Sources/TGReduxKitUI` — binding / environment helpers
- `Sources/TGReduxKitTesting` — `TestStore`
- `Sources/TGReduxKit` — `@_exported` umbrella
- `Examples/TGReduxKitDemo` — shopping demo (+ local `Shopping` package)

## Design rules

- Never put `@MainActor` on domain reducers
- Side effects return `Effect`; Middleware is not the primary path
- Capture dependencies in reducer factories — do not inject `DependencyContext` into reduce
- Domain / feature code lives in SPM targets without MainActor default
- `dispatch` returns `Task?` for optional cancellation

## Versioning

- SemVer + Keep a Changelog
- Current line: **5.0.0 (Unreleased)** — see `Docs/ADR_INDUSTRIAL_COMPROMISE.md`
