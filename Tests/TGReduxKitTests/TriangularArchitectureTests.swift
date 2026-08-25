import Foundation
import Testing
import TGReduxKitCore
import TGReduxKitRuntime
import TGReduxKitTesting

private struct CounterState: Equatable, Sendable, ReduxState {
    var count = 0
    var label = ""
}

private enum CounterAction: Equatable, Sendable, ReduxAction {
    case increment
    case decrement
    case set(Int)
    case delayedIncrement
    case streamSearch
}

private let counterReducer = Reducer<CounterState, CounterAction> { state, action in
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
        return .run(id: "delayed", producing: {
            try await Task.sleep(for: .milliseconds(20))
            return .increment
        })
    case .streamSearch:
        return .run(id: "search") { send in
            await send(.set(-1)) // searching sentinel
            try await Task.sleep(for: .milliseconds(10))
            await send(.set(42))
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
        let b = Reducer<CounterState, CounterAction> { _, action in
            if case .increment = action {
                return .run(producing: { .set(42) })
            }
            return .none
        }
        let combined = combineReducers(a, b)
        var state = CounterState()
        let effect = combined.reduce(&state, .increment)
        #expect(state.count == 1)
        if case .merge = effect.operation {
            return
        }
        if case .run = effect.operation {
            return
        }
        Issue.record("Expected merge or run effect")
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
@MainActor
struct RuntimeStoreTests {
    @Test
    func dispatchRunsEffectFollowUp() async {
        let store = Store(initialState: CounterState(), reducer: counterReducer)
        await store.dispatchAndWait(.delayedIncrement)
        #expect(store.state.count == 1)
    }

    @Test
    func cancelPreventsFollowUp() async {
        let store = Store(
            initialState: CounterState(),
            reducer: Reducer<CounterState, CounterAction> { state, action in
                switch action {
                case .delayedIncrement:
                    return .run(id: "job", producing: {
                        try await Task.sleep(for: .milliseconds(40))
                        return .increment
                    })
                case .decrement:
                    return .cancel(id: "job")
                default:
                    if case .increment = action { state.count += 1 }
                    return .none
                }
            }
        )

        _ = store.dispatch(.delayedIncrement)
        _ = store.dispatch(.decrement)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(store.state.count == 0)
    }

    @Test
    func multiValueEffectCanSendMultipleActions() async {
        let store = Store(initialState: CounterState(), reducer: counterReducer)
        await store.dispatchAndWait(.streamSearch)
        #expect(store.state.count == 42)
    }

    @Test
    func dispatchReturnsCancellableTask() async {
        let store = Store(initialState: CounterState(), reducer: counterReducer)
        let task = store.dispatch(.delayedIncrement)
        task?.cancel()
        await task?.value
        #expect(store.state.count == 0)
    }
}

@Suite
struct EffectOperatorTests {
    @Test
    func debounceDelaysWork() async throws {
        let started = Date()
        let effect = Effect<CounterAction>.run(producing: {
            .increment
        })
        .debounce(for: .milliseconds(30))

        guard case .run(_, let work) = effect.operation else {
            Issue.record("Expected run")
            return
        }
        final class Box: @unchecked Sendable {
            var sent: CounterAction?
        }
        let box = Box()
        let send = Send<CounterAction> { action in box.sent = action }
        try await work(send)
        #expect(box.sent == .increment)
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
}
