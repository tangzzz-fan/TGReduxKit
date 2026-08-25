# Effect Guide (5.0)

`Effect` is the declarative side-effect type returned from a `Reducer`. The Runtime `Store` actor owns scheduling, cancellation, and follow-up `dispatch`.

## Mental model

```text
Action → Reducer (sync state + return Effect)
      → Store.run(Effect)
      → optional Action → dispatch again
```

Reducers stay pure and nonisolated. They never call `Task` / networking directly outside an `Effect.run` body.

## Creating effects

```swift
// No work
return .none

// Async work that always produces an Action
return .run(id: "load-user") {
    let user = try await api.fetchUser()
    return .userLoaded(user)
}

// Optional follow-up
return .runOptional(id: "maybe") {
    guard flag else { return nil }
    return .ping
}

// Cancel in-flight work with the same id
return .cancel(id: "load-user")

// Fan-out
return .merge(
    .run { .analyticsLogged },
    .run(id: "prefetch") { .prefetchDone(try await api.prefetch()) }
)
```

## Operators

| API | Behavior |
|-----|----------|
| `.debounce(for:)` | Sleeps before starting work. Pair with a stable `id` so rapid re-dispatch cancels the previous sleep+work (latest-wins). |
| `.throttle(for:)` | Runs work immediately, then sleeps (cooldown). Same-id replacement still applies in Store. |
| `.map(_:)` | Used by `pullback` to embed child actions into parent actions. |

## Cancellation / latest-wins

Pass a `CancellationID` (string-literal friendly) to `.run(id:)`:

```swift
return .run(id: "catalog-search") { ... }
    .debounce(for: .milliseconds(300))
```

When a new effect with the same `id` is scheduled, Store **cancels** the previous task and **awaits its termination** before starting the new one (`cancel-await-replace`).

## Dependencies

Use `DependencyContext` for clocks **and** app services via `DependencyKey`:

```swift
enum APIClientKey: DependencyKey {
    static let liveValue: @Sendable () async throws -> User = { try await LiveAPI.fetchUser() }
}

extension DependencyContext {
    var fetchUser: @Sendable () async throws -> User {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}

Reducer { state, action, context in
    switch action {
    case .load:
        let fetch = context.fetchUser
        return .run {
            .loaded(try await fetch())
        }
    case .tick:
        return .run { .stamped(context.date()) }
    }
}
```

Override at the store boundary:

```swift
await store.withDependencies { $0.fetchUser = { .preview } }
// or ObservableStore.withDependencies { ... }
```

Factory capture of services is fine for one-off wiring; prefer `DependencyKey` when the same service is shared across reducers or tests.

## Testing

`TestStore.send` records effects without running them. Assert structure, or call `runEffects()` to execute recorded work against a live actor store.

## Demo reference

See `Examples/TGReduxKitDemo` — search uses `.run(id:).debounce`, feature flags use `.run(id:)`.
