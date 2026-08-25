# TGReduxKitDemo (5.0)

Shopping sample for the triangular architecture.

## Layout

| Piece | Role |
|-------|------|
| `Shopping` (local SPM) | Models, State/Action, `DependencyKey`s, reducers, effects — **no MainActor default** |
| App target | `ObservableStore` + Views; may keep `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` |

One non-MainActor module is enough. Do not put reducers/effects in the App target.

## DI

Services are function values on `DependencyContext` (`searchProducts`, `fetchFeatureFlags`). Override via:

```swift
await store.withDependencies {
    $0.fetchFeatureFlags = { .default }
}
```

## Effect usage

```swift
store.dispatch(.catalog(.searchQueryChanged(query)))
// → ShoppingEffects.searchCatalog(...).debounce(300ms)

store.dispatch(.featureFlags(.loadRequested(.manualRefresh)))
// → ShoppingEffects.loadFeatureFlags(...)
```

See repo `Docs/EFFECT_GUIDE.md`.

## Run

Open `TGReduxKitDemo.xcodeproj`. Local packages: `Shopping`, `../../../TGReduxKit`, `../../../TGNavigationStack`.
