# Migrating from TGReduxKit 4.x to 5.0

5.0 is an architectural rewrite: **domain pure functions + actor Store + Effect**.

## Module imports

| 4.x | 5.0 |
|-----|-----|
| `import TGReduxKit` | Still works via umbrella (Core+Runtime+UI) |
| — | Or import `TGReduxKitCore` / `TGReduxKitRuntime` / `TGReduxKitUI` separately |

## Reducer

```swift
// 4.x
let reducer: Reducer<State, Action> = { state, action in
  state.count += 1
}

// 5.0
let reducer = Reducer<State, Action>.sync { state, action in
  state.count += 1
}
// or with effects:
let reducer = Reducer<State, Action> { state, action, dependencies in
  state.count += 1
  return .run { .finish }
}
```

`Reducer` is a **nonisolated value type**. Do not mark it `@MainActor`.

## Store / UI

```swift
// 4.x
let store = Store(initialState:..., reducer:..., middlewares: [...])
store.dispatch(.increment)

// 5.0 Runtime actor
let store = Store(initialState:..., reducer:...)
await store.dispatch(.increment)

// 5.0 SwiftUI
@State var store = ObservableStore(initialState:..., reducer:...)
store.dispatch(.increment) // fires Task internally
```

## Middleware → Effect

```swift
// 4.x middleware
{ store, action, next in
  next(action)
  store.runTask(id: "search") { ... await store.dispatch(...) }
}

// 5.0 inside reducer
case .searchQueryChanged(let q):
  return .run(id: "search") {
    let results = await api.search(q)
    return .searchCompleted(results)
  }
  .debounce(for: .milliseconds(300))
```

## Removed / replaced

| 4.x | 5.0 |
|-----|-----|
| `@MainActor` Reducer / Middleware | Nonisolated Reducer + Effect |
| Onion Middleware pipeline | Effect returned from reduce |
| `ScopedStore` | Use root `ObservableStore` + nested state paths (scoped UI helpers may return later) |
| `Store.runTask` / debounce / throttle on Store | `Effect.run` / `.debounce` / `.throttle` / `.cancel` |
| Time-travel debug module | Not in 5.0.0 first cut (may return as optional product) |

## Sendable

`State` and `Action` must be `Sendable`. Prefer value types.
