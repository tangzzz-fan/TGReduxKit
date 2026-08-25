import Foundation
import Testing
import TGReduxKitCore
import TGReduxKitRuntime
import TGReduxKitTesting

private struct CounterState: Equatable, Sendable, ReduxState {
    var count = 0
}

private enum CounterAction: Equatable, Sendable, ReduxAction {
    case increment
    case decrement
    case delayedIncrement
    case set(Int)
}

private let counterReducer = Reducer<CounterState, CounterAction> { state, action, _ in
    switch action {
    case .increment:
        state.count += 1
        return .none
    case .decrement:
        state.count -= 1
        return .none
    case .set(let value):
        state.count = value
        return .none
    case .delayedIncrement:
        return .run(id: "delayed") {
            try await Task.sleep(for: .milliseconds(20))
            return .increment
        }
    }
}

@Suite
struct CoreReducerTests {
    @Test
    func syncReduceUpdatesState() throws {
        let store = TestStore(initialState: CounterState(), reducer: counterReducer)
        _ = store.send(.increment)
        try store.assert(equals: CounterState(count: 1))
        _ = store.send(.decrement)
        try store.assert(equals: CounterState(count: 0))
    }

    @Test
    func combineReducersMergesEffects() {
        let a = Reducer<CounterState, CounterAction>.sync { state, action in
            if case .increment = action { state.count += 1 }
        }
        let b = Reducer<CounterState, CounterAction> { _, action, _ in
            if case .increment = action {
                return .run { .set(42) }
            }
            return .none
        }
        let combined = combineReducers(a, b)
        var state = CounterState()
        let effect = combined.reduce(&state, .increment, .immediate)
        #expect(state.count == 1)
        guard case .merge(let effects) = effect.operation else {
            // single non-none effect may be returned unwrapped
            if case .run = effect.operation {
                return
            }
            Issue.record("Expected merge or run effect")
            return
        }
        #expect(effects.count >= 1)
    }

    @Test
    func pullbackEmbedsChildActions() throws {
        struct Parent: Equatable, Sendable, ReduxState {
            var child = CounterState()
        }
        enum ParentAction: Equatable, Sendable, ReduxAction {
            case child(CounterAction)
        }

        let parent = pullback(
            counterReducer,
            state: \Parent.child,
            action: ParentAction.child,
            extract: { if case .child(let a) = $0 { a } else { nil } }
        )

        let store = TestStore(initialState: Parent(), reducer: parent)
        _ = store.send(.child(.increment))
        try store.assert { $0.child.count == 1 }
    }
}

@Suite
struct RuntimeStoreTests {
    @Test
    func dispatchRunsEffectFollowUp() async {
        let store = Store(initialState: CounterState(), reducer: counterReducer, dependencies: .immediate)
        _ = await store.dispatch(.delayedIncrement)
        try? await Task.sleep(for: .milliseconds(50))
        let state = await store.currentState()
        #expect(state.count == 1)
    }

    @Test
    func cancelPreventsFollowUp() async {
        let store = Store(
            initialState: CounterState(),
            reducer: Reducer<CounterState, CounterAction> { state, action, _ in
                switch action {
                case .delayedIncrement:
                    return .run(id: "job") {
                        try await Task.sleep(for: .milliseconds(40))
                        return .increment
                    }
                case .decrement:
                    return .cancel(id: "job")
                default:
                    if case .increment = action { state.count += 1 }
                    return .none
                }
            },
            dependencies: .live
        )

        _ = await store.dispatch(.delayedIncrement)
        _ = await store.dispatch(.decrement)
        try? await Task.sleep(for: .milliseconds(80))
        let state = await store.currentState()
        #expect(state.count == 0)
    }
}

@Suite
struct EffectOperatorTests {
    @Test
    func debounceDelaysWork() async throws {
        let started = Date()
        let effect = Effect<CounterAction>.run {
            .increment
        }
        .debounce(for: .milliseconds(30))

        guard case .run(_, let work) = effect.operation else {
            Issue.record("Expected run")
            return
        }
        let action = try await work()
        #expect(action == .increment)
        #expect(Date().timeIntervalSince(started) >= 0.025)
    }
}

@Suite
struct DependencyKeyTests {
    private enum AnswerKey: DependencyKey {
        static let liveValue = 42
    }

    @Test
    func unsetKeyReturnsLiveValue() {
        let context = DependencyContext.live
        #expect(context[AnswerKey.self] == 42)
    }

    @Test
    func overrideReplacesLiveValue() {
        var context = DependencyContext.live
        context[AnswerKey.self] = 7
        #expect(context[AnswerKey.self] == 7)
    }

    @Test
    func withDependenciesUpdatesStore() async {
        let store = Store(
            initialState: CounterState(),
            reducer: Reducer<CounterState, CounterAction> { state, action, context in
                if case .set = action {
                    state.count = context[AnswerKey.self]
                }
                return .none
            },
            dependencies: .immediate
        )
        await store.withDependencies { $0[AnswerKey.self] = 99 }
        _ = await store.dispatch(.set(0))
        let state = await store.currentState()
        #expect(state.count == 99)
    }
}
