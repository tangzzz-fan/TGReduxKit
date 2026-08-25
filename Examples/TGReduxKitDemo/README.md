# TGReduxKitDemo (5.x)

| Piece | Role |
|-------|------|
| `Shopping` SPM | Models + reducers + effects — no MainActor default |
| App | `@MainActor` `Store` + Views |

Services are captured in `makeShoppingReducer(searchProducts:fetchFeatureFlags:now:)`.

```bash
swift test --filter ArchitectureCounterexampleVerificationTests
```
