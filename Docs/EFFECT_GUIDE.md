# Effect Guide (5.x industrial compromise)

`Effect` is returned from a nonisolated `Reducer`. The `@MainActor` `Store` owns scheduling, cancellation, and follow-up `dispatch` via `Send`.

## Mental model

```text
Action → Reducer (sync state + return Effect)
      → Store.run(Effect)
      → send(Action)* → dispatch again
```

## Creating effects

```swift
// None
return .none

// Multi-value (preferred for progress / streams)
return .run(id: "search") { send in
    await send(.searching)
    let results = try await api.search(query)
    await send(.completed(results))
}

// Single follow-up convenience
return .run(id: "load", producing: {
    .loaded(try await api.fetch())
})

return .cancel(id: "search")
return .merge(effectA, effectB)
```

## Operators

| API | Behavior |
|-----|----------|
| `.cancellable(id:)` | Sets/replaces the cancellation id |
| `.debounce(for:)` | Sleeps before work (pair with stable id) |
| `.throttle(for:)` | Runs work then sleeps |
| `.map` | Used by `pullback` |

## Dependencies

**Do not** inject services through Store/`DependencyContext` into every reduce. Capture `@Sendable` closures in the reducer factory:

```swift
func makeUserReducer(fetch: @escaping @Sendable () async throws -> User) -> Reducer<State, Action> {
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

`DependencyContext` remains available for app-owned bags if you want them — it is not part of the reduce signature.

## Testing

`TestStore.send` records effects without running them. Assert structure; optionally `await runEffects()` on MainActor.
