# Architecture (5.0)

Audited Middleware + Effect:

1. **TGReduxKitCore** — nonisolated `State` / `Action` / pure `Reducer` (`Void`) / `Effect`
2. **TGReduxKitRuntime** — `@MainActor @Observable` `Store`; Middleware returns `Effect`
3. **TGReduxKitUI** — `provideStore` / `binding`
4. **TGReduxKitDebug** — logging / diff / error-reporting middleware

```text
View → Store.dispatch
    → Middleware onion (each returns Effect)
    → Reducer (inout State)
    → Store runs Effect (task / cancel / merge)
    → follow-up Action → dispatch again
```

Full ADR: [Docs/ADR_AUDITED_MIDDLEWARE_EFFECT.md](Docs/ADR_AUDITED_MIDDLEWARE_EFFECT.md).  
DI: [Docs/DEPENDENCY_INJECTION.md](Docs/DEPENDENCY_INJECTION.md).
