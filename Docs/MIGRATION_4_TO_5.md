# Migrating from TGReduxKit 4.x to 5.0

5.0 is an architectural rewrite (industrial compromise): **nonisolated `Reducer` → streaming `Effect`**, **`@MainActor @Observable` `Store`**, domain code in a non-MainActor SPM target.

See also `Docs/ADR_INDUSTRIAL_COMPROMISE.md`.

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

// 5.0 — sync only
let reducer = Reducer<State, Action>.sync { state, action in
  state.count += 1
}

// 5.0 — with effects (capture services in the factory; no DependencyContext param)
func makeReducer(fetch: @escaping @Sendable () async throws -> User) -> Reducer<State, Action> {
  Reducer { state, action in
    switch action {
    case .load:
      return .run { send in
        await send(.loaded(try await fetch()))
      }
    default:
      return .none
    }
  }
}
```

`Reducer` is a **nonisolated value type**. Do not mark it `@MainActor`.

## Store / UI

```swift
// 4.x
let store = Store(initialState:..., reducer:..., middlewares: [...])
store.dispatch(.increment)

// 5.0 — MainActor observable root (ObservableStore is a typealias)
let store = Store(initialState: State(), reducer: reducer)
_ = store.dispatch(.increment)           // returns Task? — discard or cancel
await store.dispatchAndWait(.load)       // optional await of scheduled work
```

## Middleware → Effect

Onion Middleware is removed as the primary async path. Return `Effect` from the reducer instead.

## Domain isolation

Keep State/Action/reducers in an SPM target **without** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (see Demo `Shopping`).
