# 0825 Review Union → Triangular Architecture

Source reviews:

- [0825_reviews_01.md](./0825_reviews_01.md)
- [0825_reviews_02.md](./0825_reviews_02.md)

Absorbed into [ADR_TRIANGULAR_ARCHITECTURE.md](./ADR_TRIANGULAR_ARCHITECTURE.md).

| Review theme | 5.0 landing |
|--------------|-------------|
| Reducer off MainActor | Core `struct Reducer` nonisolated |
| Effect / declarative async | Core `Effect` + Runtime runner |
| Action Sendable | `Action: Sendable`, `State: Sendable` |
| Store task ownership | `actor Store` cancel map |
| DI | `DependencyContext` in reduce |
| TestStore + effect assert | TGReduxKitTesting |
| Split async primitives | Effect operators (debounce/throttle/cancel) |
| StoreType binding | UI `ObservableStore.binding` |
| No domain `nonisolated` spam | Framework isolation boundaries |
