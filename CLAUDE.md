# CLAUDE.md

Guidance for agents working in this repository.

## Project Overview

TGReduxKit 5.x — audited architecture:

1. **Core** — nonisolated `State` / `Action` / pure `Reducer` (`Void`) / `Effect`
2. **Runtime** — `@MainActor @Observable` `Store`, Middleware returns `Effect`, `ScopedStore`
3. **UI** — environment + bindings
4. **Debug** — optional logging / reporting middleware

## Build & Test

```bash
swift build
swift test
# Demo
xcodebuild -project Examples/TGReduxKitDemo/TGReduxKitDemo.xcodeproj -scheme TGReduxKitDemo -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Tests use **Swift Testing** (`@Test` / `#expect`), not XCTest.

## Design rules

- Reducers stay pure (`Void`); side effects via Middleware → `Effect`
- Domain models live in SPM targets without MainActor default
- Prefer `@SwiftUI.State` when the `State` protocol is in scope

## Docs

- `Docs/ADR_AUDITED_MIDDLEWARE_EFFECT.md`
