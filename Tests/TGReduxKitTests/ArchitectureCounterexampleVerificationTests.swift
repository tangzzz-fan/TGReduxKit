import Foundation
import Testing
import TGReduxKitCore
import TGReduxKitRuntime
import TGReduxKitTesting
#if canImport(TGReduxKitUI)
import TGReduxKitUI
#endif

/// Counterexample verification updated for industrial compromise (MainActor Store + streaming Effect).
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

    @Test
    @MainActor
    func counterexample01_mainActorStoreAllowsSyncUIAccess() {
        let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
            if case .increment = action { state.count += 1 }
        }
        let store = Store(initialState: CounterState(), reducer: reducer)
        #expect(store.state.count == 0)
        _ = store.dispatch(.increment)
        #expect(store.state.count == 1)
    }

    @Test
    func counterexample03_syncTestStoreDoesNotAwaitEffects() throws {
        let reducer = Reducer<CounterState, CounterAction> { state, action in
            switch action {
            case .increment:
                state.count += 1
                return .none
            case .fetch:
                return .run(producing: {
                    try await Task.sleep(for: .milliseconds(50))
                    return .fetchDone("ok")
                })
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
    }

    @Test
    @MainActor
    func counterexample04_dispatchReturnsOptionalTaskHandle() {
        let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
            if case .increment = action { state.count += 1 }
        }
        let store = Store(initialState: CounterState(), reducer: reducer)
        let task: Task<Void, Never>? = store.dispatch(.increment)
        _ = task
        #expect(store.state.count == 1)
    }

    @Test
    @MainActor
    func counterexample05_multiValueEffectCanEmitProgressThenResult() async {
        let reducer = Reducer<CounterState, CounterAction> { state, action in
            switch action {
            case .search:
                return .run(id: "s") { send in
                    await send(.searching)
                    await send(.searchDone("results"))
                }
            case .searching:
                state.label = "…"
                return .none
            case .searchDone(let value):
                state.label = value
                return .none
            default:
                return .none
            }
        }

        let store = Store(initialState: CounterState(), reducer: reducer)
        await store.dispatchAndWait(.search)
        #expect(store.state.label == "results")
    }

    @Test
    func counterexample06_coreTypesUsableFromPlainActor() async {
        actor Probe {
            func reduceOnce() -> CounterState {
                let reducer = Reducer<CounterState, CounterAction>.sync { state, action in
                    if case .increment = action { state.count += 1 }
                }
                var state = CounterState()
                _ = reducer.reduce(&state, .increment)
                return state
            }
        }
        let state = await Probe().reduceOnce()
        #expect(state.count == 1)
    }
}
