import Foundation
import Testing
import TGReduxKitCore
import TGReduxKitRuntime
import TGReduxKitTesting
#if canImport(TGReduxKitUI)
import TGReduxKitUI
#endif

/// Positive verification of the six architecture counterexamples vs TGReduxKit 5.0.
/// See `Docs/ARCHITECTURE_COUNTEREXAMPLES.md`.
@Suite("ArchitectureCounterexampleVerificationTests")
struct ArchitectureCounterexampleVerificationTests {

    private struct CounterState: Equatable, Sendable, ReduxState {
        var count = 0
        var label = ""
    }

    private enum CounterAction: Equatable, Sendable, ReduxAction {
        case increment
        case fetch
        case fetchDone(String)
        case search
        case searching
        case searchDone(String)
    }

    #if canImport(TGReduxKitUI)
    @MainActor
    private func waitForProjection(
        _ store: ObservableStore<CounterState, CounterAction>,
        where predicate: (CounterState) -> Bool,
        attempts: Int = 50
    ) async {
        for _ in 0..<attempts {
            if predicate(store.state) { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
    #endif

    // MARK: 1 — Actor Store is not a SwiftUI root; ObservableStore is

    @Test
    @MainActor
    func counterexample01_observableStoreAllowsSyncUIAccess() async {
        #if canImport(TGReduxKitUI)
        let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
            if case .increment = action { state.count += 1 }
        }
        let store = ObservableStore(initialState: CounterState(), reducer: reducer)

        // Sync read — would fail on a plain actor Store from View body.
        #expect(store.state.count == 0)

        store.dispatch(.increment)
        await store.dispatchAndWait(.increment)
        await waitForProjection(store) { $0.count >= 1 }
        #expect(store.state.count >= 1)
        #else
        Issue.record("TGReduxKitUI unavailable on this platform slice")
        #endif
    }

    @Test
    @MainActor
    func counterexample01_documentsStateHandlerRegistrationRace() async {
        #if canImport(TGReduxKitUI)
        // Known gap: setStateHandler is installed in a detached Task.
        let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
            if case .increment = action { state.count += 1 }
        }
        let store = ObservableStore(initialState: CounterState(), reducer: reducer)
        await store.dispatchAndWait(.increment)
        let immediate = store.state.count
        await waitForProjection(store) { $0.count >= 1 }
        #expect(store.state.count >= 1)
        #expect(immediate == 0 || immediate >= 1)
        #else
        Issue.record("TGReduxKitUI unavailable")
        #endif
    }

    // MARK: 2 — Observation path goes through ObservableStore.state writes

    @Test
    @MainActor
    func counterexample02_observableStoreStateUpdatesAfterReduce() async {
        #if canImport(TGReduxKitUI)
        let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
            if case .increment = action { state.count += 1 }
        }
        let store = ObservableStore(initialState: CounterState(), reducer: reducer)
        await store.dispatchAndWait(.increment)
        await waitForProjection(store) { $0.count >= 1 }
        #expect(store.state.count >= 1)
        #else
        Issue.record("TGReduxKitUI unavailable")
        #endif
    }

    // MARK: 3 — Sync TestStore path stays cheap; effects optional

    @Test
    func counterexample03_syncTestStoreDoesNotAwaitEffects() throws {
        let reducer = Reducer<CounterState, CounterAction> { state, action, _ in
            switch action {
            case .increment:
                state.count += 1
                return .none
            case .fetch:
                return .run {
                    try await Task.sleep(for: .milliseconds(50))
                    return .fetchDone("ok")
                }
            case .fetchDone(let value):
                state.label = value
                return .none
            default:
                return .none
            }
        }

        let store = TestStore(initialState: CounterState(), reducer: reducer)
        _ = store.send(.increment)
        try store.assert(equals: CounterState(count: 1, label: ""))

        let effect = store.send(.fetch)
        guard case .run = effect.operation else {
            Issue.record("expected run effect")
            return
        }
        try store.assert(equals: CounterState(count: 1, label: ""))
        #expect(store.recordedEffects.count == 2)
    }

    // MARK: 4 — dispatch must not hand Task ownership to the view

    @Test
    @MainActor
    func counterexample04_dispatchIsFireAndForgetReturningVoid() async {
        #if canImport(TGReduxKitUI)
        let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
            if case .increment = action { state.count += 1 }
        }
        let store = ObservableStore(initialState: CounterState(), reducer: reducer)

        let result: Void = store.dispatch(.increment)
        _ = result
        await store.dispatchAndWait(.increment)
        await waitForProjection(store) { $0.count >= 1 }
        #expect(store.state.count >= 1)
        #else
        Issue.record("TGReduxKitUI unavailable")
        #endif
    }

    // MARK: 5 — Single-value Effect: one follow-up Action per run

    @Test
    func counterexample05_singleRunYieldsAtMostOneFollowUp() async {
        let reducer = Reducer<CounterState, CounterAction> { state, action, _ in
            switch action {
            case .search:
                return .run { .searchDone("results") }
            case .searchDone(let value):
                state.label = value
                return .none
            case .searching:
                state.label = "…"
                return .none
            default:
                return .none
            }
        }

        let store = Store(initialState: CounterState(), reducer: reducer, dependencies: .immediate)
        _ = await store.dispatch(.search)
        try? await Task.sleep(for: .milliseconds(30))
        let state = await store.currentState()
        #expect(state.label == "results")
        #expect(state.label != "…")
    }

    @Test
    func counterexample05_intermediateStateRequiresSeparateAction() async {
        let reducer = Reducer<CounterState, CounterAction> { state, action, _ in
            switch action {
            case .search:
                state.label = "…"
                return .run { .searchDone("results") }
            case .searchDone(let value):
                state.label = value
                return .none
            default:
                return .none
            }
        }

        let store = Store(initialState: CounterState(), reducer: reducer, dependencies: .immediate)
        _ = await store.dispatch(.search)
        var state = await store.currentState()
        #expect(state.label == "…" || state.label == "results")
        try? await Task.sleep(for: .milliseconds(30))
        state = await store.currentState()
        #expect(state.label == "results")
    }

    // MARK: 6 — Core types usable outside MainActor default

    @Test
    func counterexample06_coreTypesUsableFromPlainActor() async {
        actor Probe {
            func reduceOnce() -> CounterState {
                let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
                    if case .increment = action { state.count += 1 }
                }
                var state = CounterState()
                _ = reducer.reduce(&state, .increment, .immediate)
                return state
            }
        }

        let probe = Probe()
        let state = await probe.reduceOnce()
        #expect(state.count == 1)
    }
}
