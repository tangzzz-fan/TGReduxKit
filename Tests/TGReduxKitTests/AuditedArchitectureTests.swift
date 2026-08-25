import Foundation
import Testing
import TGReduxKitCore
import TGReduxKitRuntime
import TGReduxKitTesting
import TGReduxKitDebug

private struct CounterState: Equatable, Sendable, State {
    var count = 0
    var label = ""
}

private enum CounterAction: Equatable, Sendable, Action {
    case increment
    case decrement
    case set(Int)
    case delayedIncrement
    case fetch
    case fetchDone(String)
}

private let counterReducer: Reducer<CounterState, CounterAction> = { state, action in
    switch action {
    case .increment:
        state.count += 1
    case .decrement:
        state.count -= 1
    case .set(let value):
        state.count = value
    case .fetchDone(let value):
        state.label = value
    case .delayedIncrement, .fetch:
        break
    }
}

@Suite("CoreReducerTests")
struct CoreReducerTests {
    @Test
    func syncReduceUpdatesState() throws {
        let store = TestStore(initialState: CounterState(), reducer: counterReducer)
        store.send(.increment)
        try store.assert(equals: CounterState(count: 1))
        store.send(.decrement)
        try store.assert(equals: CounterState(count: 0))
    }

    @Test
    func combineReducersRunsLeftToRight() throws {
        let a: Reducer<CounterState, CounterAction> = { state, action in
            if case .increment = action { state.count += 1 }
        }
        let b: Reducer<CounterState, CounterAction> = { state, action in
            if case .increment = action { state.label = "ok" }
        }
        let store = TestStore(initialState: CounterState(), reducer: combineReducers(a, b))
        store.send(.increment)
        try store.assert(equals: CounterState(count: 1, label: "ok"))
    }

    @Test
    func pullbackEmbedsChildActions() throws {
        struct Parent: Equatable, Sendable, State {
            var child = CounterState()
        }
        enum ParentAction: Equatable, Sendable, Action {
            case child(CounterAction)
        }

        let parent = pullback(
            counterReducer,
            state: \Parent.child,
            action: ParentAction.child,
            extract: { if case .child(let a) = $0 { a } else { nil } }
        )

        let store = TestStore(initialState: Parent(), reducer: parent)
        store.send(.child(.increment))
        try store.assert { $0.child.count == 1 }
    }
}

@Suite("RuntimeStoreTests")
@MainActor
struct RuntimeStoreTests {
    @Test
    func dispatchAppliesReducer() {
        let store = Store(initialState: CounterState(), reducer: counterReducer)
        store.dispatch(.increment)
        #expect(store.state.count == 1)
    }

    @Test
    func middlewareEffectFollowUp() async {
        let middleware: Middleware<CounterState, CounterAction> = { _, action, next in
            let base = next(action)
            guard case .delayedIncrement = action else { return base }
            return .merge(
                base,
                .task(id: "delayed") {
                    try? await Task.sleep(for: .milliseconds(20))
                    return .increment
                }
            )
        }

        let store = Store(
            initialState: CounterState(),
            reducer: counterReducer,
            middlewares: [middleware]
        )
        store.dispatch(.delayedIncrement)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.state.count == 1)
    }

    @Test
    func cancelPreventsFollowUp() async {
        enum Job: Equatable, Sendable, Action {
            case start
            case cancel
            case done
        }
        struct S: Equatable, Sendable, State {
            var count = 0
        }
        let reducer: Reducer<S, Job> = { state, action in
            if case .done = action { state.count += 1 }
        }
        let middleware: Middleware<S, Job> = { _, action, next in
            switch action {
            case .start:
                return .merge(
                    next(action),
                    .task(id: "job") {
                        try? await Task.sleep(for: .milliseconds(40))
                        return .done
                    }
                )
            case .cancel:
                return .merge(next(action), .cancel(id: "job"))
            case .done:
                return next(action)
            }
        }

        let store = Store(initialState: S(), reducer: reducer, middlewares: [middleware])
        store.dispatch(.start)
        store.dispatch(.cancel)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(store.state.count == 0)
    }

    @Test
    func scopedStoreTracksParentUpdates() {
        struct Parent: Equatable, Sendable, State {
            var child = CounterState()
        }
        enum ParentAction: Equatable, Sendable, Action {
            case child(CounterAction)
        }

        let parentReducer = pullback(
            counterReducer,
            state: \Parent.child,
            action: ParentAction.child,
            extract: { if case .child(let a) = $0 { a } else { nil } }
        )

        let store = Store(initialState: Parent(), reducer: parentReducer)
        let scoped = store.scope(state: \.child, action: ParentAction.child)
        scoped.dispatch(.increment)
        #expect(store.state.child.count == 1)
        #expect(scoped.state.count == 1)
    }
}

@Suite("EffectOperatorTests")
struct EffectOperatorTests {
    @Test
    func mergeFlattensNone() {
        let effect = Effect<CounterAction>.merge(.none(), .task { .increment }, .none())
        guard case .task = effect.operation else {
            Issue.record("Expected single task after flattening")
            return
        }
    }

    @Test
    func debounceDelaysWork() async {
        let started = Date()
        let effect = Effect<CounterAction>.debounce(id: "d", delay: .milliseconds(30)) {
            .increment
        }
        guard case .task(_, _, let work) = effect.operation else {
            Issue.record("Expected task")
            return
        }
        let action = await work()
        #expect(action == .increment)
        #expect(Date().timeIntervalSince(started) >= 0.025)
    }
}

@Suite("MiddlewareStructureTests")
@MainActor
struct MiddlewareStructureTests {
    @Test
    func apiStyleMiddlewareReturnsMergeWithTask() {
        let middleware: Middleware<CounterState, CounterAction> = { _, action, next in
            guard case .fetch = action else { return next(action) }
            return .merge(
                next(action),
                .task(id: "fetch") { .fetchDone("ok") }
            )
        }

        let store = Store(initialState: CounterState(), reducer: counterReducer)
        let effect = middleware(store, .fetch) { _ in .none() }
        // `.merge` collapses a lone non-none child to that child.
        switch effect.operation {
        case .merge(let effects):
            #expect(effects.count >= 1)
        case .task:
            break
        default:
            Issue.record("Expected merge or task effect")
        }
    }

    @Test
    func loggingMiddlewarePassesThrough() {
        final class LogBox: @unchecked Sendable {
            var logs: [String] = []
        }
        let box = LogBox()
        let middleware: Middleware<CounterState, CounterAction> = actionLoggingMiddleware {
            box.logs.append($0)
        }
        let store = Store(initialState: CounterState(), reducer: counterReducer)
        _ = middleware(store, .increment) { action in
            store.dispatch(action)
            return Effect<CounterAction>.none()
        }
        #expect(!box.logs.isEmpty)
    }

    @Test
    func factoryInjectedMockIsUsedByEffect() async {
        struct Flags: Equatable, Sendable {
            var premiumOnly: Bool
        }
        struct FlagState: Equatable, Sendable, State {
            var flags = Flags(premiumOnly: false)
        }
        enum FlagAction: Equatable, Sendable, Action {
            case load
            case loaded(Flags)
        }

        struct MockClient: Sendable {
            let flags: Flags
            func fetch() async -> Flags { flags }
        }

        let reducer: Reducer<FlagState, FlagAction> = { state, action in
            if case .loaded(let flags) = action {
                state.flags = flags
            }
        }

        // Factory-style capture — same pattern as makeFeatureFlagsMiddleware(deps)
        let client = MockClient(flags: Flags(premiumOnly: true))
        let middleware: Middleware<FlagState, FlagAction> = { _, action, next in
            let base = next(action)
            guard case .load = action else { return base }
            return .merge(
                base,
                .task { .loaded(await client.fetch()) }
            )
        }

        let store = Store(initialState: FlagState(), reducer: reducer, middlewares: [middleware])
        store.dispatch(.load)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(store.state.flags.premiumOnly == true)
    }
}
