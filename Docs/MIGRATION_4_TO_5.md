# Migrating from TGReduxKit 4.x to 5.0

> **现行**：5.0.0 定稿为「纯 Reducer + Middleware→Effect」。以下迁移说明对应当前源码。

5.0 is an architectural rewrite (**audited Middleware + Effect**):

- Pure nonisolated `Reducer` → `Void`
- Middleware returns declarative `Effect`
- Single `@MainActor @Observable` `Store`
- Dependencies via **factory closures** (no DI container / `DependencyValues`)

Canonical ADR: `Docs/ADR_AUDITED_MIDDLEWARE_EFFECT.md`. DI: `Docs/DEPENDENCY_INJECTION.md`.

## Module imports

| 4.x | 5.0 |
|-----|-----|
| `import TGReduxKit` | Still works via umbrella (Core+Runtime+UI+Debug) |
| — | Or import `TGReduxKitCore` / `TGReduxKitRuntime` / `TGReduxKitUI` / `TGReduxKitDebug` separately |

## Reducer — keep pure

```swift
// 4.x — sync reducer (same shape for state updates)
let reducer: Reducer<AppState, AppAction> = { state, action in
  state.count += 1
}

// 5.0 — still Void; never return Effect from the reducer
let reducer: Reducer<AppState, AppAction> = { state, action in
  state.count += 1
}
```

Do **not** call `Date()` / `UUID()` / network APIs inside the reducer. Put those values on the `Action`, supplied by Middleware or the View.

## Effects — move into Middleware factories

```swift
// 4.x — often middleware owned Tasks via store.runTask / debounce helpers
// 5.0 — middleware returns Effect; Store runs and cancels by CancellationID

func makeSearchMiddleware(
  search: @escaping @Sendable (String) async -> [Product]
) -> Middleware<AppState, AppAction> {
  { _, action, next in
    let base = next(action)
    guard case .queryChanged(let q) = action else { return base }
    return .merge(
      base,
      .debounce(id: "search", delay: .milliseconds(300)) {
        .searchCompleted(await search(q))
      }
    )
  }
}
```

## Store / UI

```swift
// 4.x
let store = Store(initialState:..., reducer:..., middlewares: [...])
store.dispatch(.increment)

// 5.0 — same composition shape; Store is @MainActor @Observable
@SwiftUI.State var store = Store(
  initialState: AppState(),
  reducer: appReducer,
  middlewares: [
    makeSearchMiddleware(search: LiveSearch().run),
    actionLoggingMiddleware { print($0) }
  ]
)
store.dispatch(.queryChanged("tea"))
```

Qualify `@SwiftUI.State` when the `State` protocol is in scope.

## Dependency injection

| Do | Don't |
|----|--------|
| Inject at Composition Root into middleware factories | Put `APIClient` on `Store` |
| Capture `Sendable` services in Effect closures | Use a global `DependencyValues` registry |
| Pass mocks into factories in tests / Previews | Call live networking from the reducer |

Demo reference: Composition Root calls `makeCatalogSearchMiddleware(productSearch:)` / `makeFeatureFlagsMiddleware(featureFlags:now:)` directly — no `*Dependencies` bag.

## Domain isolation

Keep State / Action / models in an SPM target **without** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` when the app target defaults to MainActor (see Demo `Shopping`).

## Removed / superseded from interim 5.0 drafts

If you adopted an early 5.0 preview (`actor Store` + `ObservableStore`, or `Reducer` returning `Effect` / `DependencyContext`):

1. Collapse to one `@MainActor` `Store`.
2. Move effects out of the reducer into Middleware factories.
3. Replace `DependencyKey` / `withDependencies` with factory parameters.
