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

Same `CancellationID` on a new `.task` **replaces** the previous task (latest-wins). `.cancel(id:)` marks the Task cancelled.

## Cooperative cancel ≠ no races

Store cancellation is **cooperative**:

```swift
.task(id: "job") {
    for step in 1...n {
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return nil }  // after every await
        // …
    }
    guard !Task.isCancelled else { return nil }
    return .finished
}
```

| Fact | Implication |
|------|-------------|
| Forgetting `Task.isCancelled` in long loops | Work continues; mid-loop `store.dispatch` **bypasses** Store’s guard on the Effect return value → stale writes |
| Checking `Task.isCancelled` in the loop | Necessary, **still not enough alone** — window between check and next `await`; result may arrive after a newer intent |
| Store drops returned Action if `Task.isCancelled` | Helps the return path only; does not rewrite your manual `dispatch` calls |
| Reducer guards (`query == state.searchQuery`) | Logical latest-wins when a late Action still slips through |

Demo: **Async Lab** in `TGReduxKitDemo` (toggle respect vs leak). Search uses debounce id + reducer query guard + post-await `isCancelled` check.

## Middleware shape

```swift
func makeAPIMiddleware(api: APIClient) -> Middleware<AppState, AppAction> {
    { _, action, next in
        let base = next(action)
        guard case .fetchUser(let id) = action else { return base }
        return .merge(
            base,
            .task(id: "fetch-user") {
                do {
                    let user = try await api.fetchUser(id: id)
                    guard !Task.isCancelled else { return nil }
                    return .userLoaded(user)
                } catch {
                    guard !Task.isCancelled else { return nil }
                    return .loadFailed(error)
                }
            }
        )
    }
}
```

Capture `@Sendable` dependencies in the factory — do not put them on `Store`. See [DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md).

## Race (problem A) vs cancel (problem B)

| | Question | Mechanism |
|--|----------|-----------|
| **A** | Old async results polluting state? | Same effect `id` + post-await `isCancelled` + reducer token/query guard |
| **B** | Lifecycle / teardown? | `.cancel(id:)` / replace same id; honor `Task.isCancelled` in the body |

Prefer effect IDs for IO that must be latest-wins (search, refresh). Use reducer guards when multiple independent streams share state.
