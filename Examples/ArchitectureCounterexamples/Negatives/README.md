# Compile-fail counterexamples (not in Package.swift)

These files are **documentation fixtures**. They are intentionally **not** members of any SPM target.
Copy into a Playground / temporary target with Swift 6 strict concurrency to see the expected diagnostics.

| File | Expected |
|------|----------|
| `Counterexample01_PlainActorInSwiftUI.swift` | Actor-isolated `state` / `dispatch` from View |
| `Counterexample02_BrokenObservableActor.swift` | `@Observable` + actor + nonisolated state issues |
| `Counterexample04_DispatchReturnsTask.swift` | await required / Task ownership issues |

Counterexamples 3 and 5 are complexity/capability arguments — covered by positive tests + docs, not compile-fail.
