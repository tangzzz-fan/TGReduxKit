# Effect Guide (5.0)

`Effect` is a **declarative** description. Middleware returns it; `@MainActor` `Store` interprets and runs it. Reducers never return effects.

## Mental model

```text
Action → Middleware → next → Reducer (sync state)
                    ↘ return Effect
Store.run(Effect) → optional follow-up Action → dispatch
```

## Creating effects

```swift
Effect<AppAction>.none()

Effect.task(id: "load") {
    .loaded(await api.fetch())
}

Effect.cancel(id: "load")

Effect.merge(downstream, fetchEffect)

Effect.debounce(id: "search", delay: .milliseconds(300)) {
    .searchCompleted(await search(query))
}

Effect.fireAndForget {
    await analytics.track("opened")
}
```

Same `CancellationID` on a new `.task` **replaces** the previous task (latest-wins). `.cancel(id:)` stops it; `Task.isCancelled` should be checked in long loops.

## Middleware shape

```swift
func makeAPIMiddleware(api: APIClient) -> Middleware<AppState, AppAction> {
    { _, action, next in
        let base = next(action)
        guard case .fetchUser(let id) = action else { return base }
        return .merge(
            base,
            .task(id: "fetch-user") {
                do { return .userLoaded(try await api.fetchUser(id: id)) }
                catch { return .loadFailed(error) }
            }
        )
    }
}
```

Capture `@Sendable` dependencies in the factory — do not put them on `Store`. See [DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md).

## Race (problem A) vs cancel (problem B)

| | Question | Mechanism |
|--|----------|-----------|
| **A** | Old async results polluting state? | Same effect `id` → previous task cancelled; optionally guard in reducer with request token / query |
| **B** | Lifecycle / teardown? | `.cancel(id:)` or Store deinit clearing `managedTasks` |

Prefer effect IDs for IO that must be latest-wins (search, refresh). Use reducer guards when multiple independent streams share state.
