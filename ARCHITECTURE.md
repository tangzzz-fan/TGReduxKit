# Architecture (5.0)

TGReduxKit uses a triangular architecture:

1. **TGReduxKitCore** — nonisolated domain (`Reducer`, `Effect`, `DependencyContext`)
2. **TGReduxKitRuntime** — `actor Store` (state + effect runner)
3. **TGReduxKitUI** — `ObservableStore` MainActor projection for SwiftUI

See [Docs/ADR_TRIANGULAR_ARCHITECTURE.md](Docs/ADR_TRIANGULAR_ARCHITECTURE.md) for the full decision record.

```text
View → ObservableStore.dispatch
    → await Store.dispatch
    → Reducer → Effect
    → run Effect → optional Action → dispatch
    → MainActor update ObservableStore.state
```
