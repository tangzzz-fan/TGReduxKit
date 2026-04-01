import Testing
import Foundation
@testable import TGReduxKit

struct TGReduxKitTests {
    final class LogCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ entry: String) {
            lock.lock()
            storage.append(entry)
            lock.unlock()
        }

        var entries: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    struct TestState: Equatable {
        var count: Int = 0
        var lastAction: String = ""
    }

    struct RootState: Equatable {
        var feature = FeatureState()
        var title = ""
    }

    struct FeatureState: Equatable {
        var count: Int = 0
        var isEnabled = false
    }

    enum TestAction: Equatable {
        case increment
        case decrement
        case setMessage(String)
    }

    enum RootAction: Equatable {
        case feature(FeatureAction)
        case setTitle(String)
    }

    enum FeatureAction: Equatable {
        case increment
        case toggle(Bool)
    }

    let reducer: (inout TestState, TestAction) -> Void = { state, action in
        switch action {
        case .increment:
            state.count += 1
        case .decrement:
            state.count -= 1
        case .setMessage(let message):
            state.lastAction = message
        }
    }

    let rootReducer: (inout RootState, RootAction) -> Void = { state, action in
        switch action {
        case .feature(let featureAction):
            switch featureAction {
            case .increment:
                state.feature.count += 1
            case .toggle(let isEnabled):
                state.feature.isEnabled = isEnabled
            }
        case .setTitle(let title):
            state.title = title
        }
    }

    @MainActor
    @Test func testStoreInitialization() {
        let store = Store(initialState: TestState(), reducer: reducer)
        #expect(store.state == TestState(count: 0, lastAction: ""))
    }

    @MainActor
    @Test func testDispatch() {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.dispatch(.increment)
        #expect(store.state.count == 1)

        store.dispatch(.decrement)
        #expect(store.state.count == 0)

        store.dispatch(.setMessage("Hello"))
        #expect(store.state.lastAction == "Hello")
    }

    @MainActor
    @Test func testMiddleware() {
        var middlewareLog: [String] = []

        let loggingMiddleware: Middleware<TestState, TestAction> = { _, action, next in
            middlewareLog.append("Before")
            next(action)
            middlewareLog.append("After")
        }

        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [loggingMiddleware]
        )

        store.dispatch(.increment)

        #expect(store.state.count == 1)
        #expect(middlewareLog == ["Before", "After"])
    }

    @MainActor
    @Test func testMiddlewareChaining() {
        var log: [String] = []

        let m1: Middleware<TestState, TestAction> = { _, _, next in
            log.append("M1 Pre")
            next(.increment)
            log.append("M1 Post")
        }

        let m2: Middleware<TestState, TestAction> = { _, _, next in
            log.append("M2 Pre")
            next(.increment)
            log.append("M2 Post")
        }

        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [m1, m2]
        )

        store.dispatch(.increment)

        #expect(log == ["M1 Pre", "M2 Pre", "M2 Post", "M1 Post"])
        #expect(store.state.count == 1)
    }

    @MainActor
    @Test func testAsyncActionInMiddleware() async throws {
        let asyncMiddleware: Middleware<TestState, TestAction> = { store, action, next in
            if case .increment = action {
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    await store.dispatch(.setMessage("Async Done"))
                }
            }
            next(action)
        }

        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [asyncMiddleware]
        )

        store.dispatch(.increment)
        #expect(store.state.count == 1)
        #expect(store.state.lastAction == "")

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.state.lastAction == "Async Done")
    }

    @MainActor
    @Test func testScopedStoreSyncsStateAndAction() {
        let store = Store(initialState: RootState(), reducer: rootReducer)
        let featureStore = store.scope(state: \.feature, action: RootAction.feature)

        #expect(featureStore.state == FeatureState())

        featureStore.dispatch(.increment)
        #expect(featureStore.state.count == 1)
        #expect(store.state.feature.count == 1)

        store.dispatch(.feature(.toggle(true)))
        #expect(featureStore.state.isEnabled)
    }

    @MainActor
    @Test func testScopedStoreCanNest() {
        struct NestedRootState: Equatable {
            var parent = ParentState()
        }

        struct ParentState: Equatable {
            var child = FeatureState()
        }

        enum NestedRootAction: Equatable {
            case parent(ParentAction)
        }

        enum ParentAction: Equatable {
            case child(FeatureAction)
        }

        let nestedReducer: (inout NestedRootState, NestedRootAction) -> Void = { state, action in
            switch action {
            case .parent(let parentAction):
                switch parentAction {
                case .child(let featureAction):
                    switch featureAction {
                    case .increment:
                        state.parent.child.count += 1
                    case .toggle(let isEnabled):
                        state.parent.child.isEnabled = isEnabled
                    }
                }
            }
        }

        let store = Store(initialState: NestedRootState(), reducer: nestedReducer)
        let parentStore = store.scope(state: \.parent, action: NestedRootAction.parent)
        let childStore = parentStore.scope(state: \.child, action: ParentAction.child)

        childStore.dispatch(.increment)

        #expect(store.state.parent.child.count == 1)
        #expect(childStore.state.count == 1)
    }

    @MainActor
    @Test func testRunTaskCancelsPreviousTaskWithSameID() async throws {
        struct TaskState: Equatable {
            var values: [String] = []
        }

        enum TaskAction: Equatable {
            case append(String)
        }

        let taskReducer: (inout TaskState, TaskAction) -> Void = { state, action in
            switch action {
            case .append(let value):
                state.values.append(value)
            }
        }

        let store = Store(initialState: TaskState(), reducer: taskReducer)

        store.runTask(id: "load") { [store] in
            try? await Task.sleep(nanoseconds: 200_000_000)

            guard !Task.isCancelled else { return }
            await store.dispatch(.append("first"))
        }

        store.runTask(id: "load") { [store] in
            try? await Task.sleep(nanoseconds: 50_000_000)

            guard !Task.isCancelled else { return }
            await store.dispatch(.append("second"))
        }

        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(store.state.values == ["second"])
    }

    @MainActor
    @Test func testActionLoggingMiddleware() {
        let collector = LogCollector()
        let middleware: Middleware<TestState, TestAction> = actionLoggingMiddleware { collector.append($0) }
        let store = Store(initialState: TestState(), reducer: reducer, middlewares: [middleware])

        store.dispatch(.increment)

        #expect(collector.entries == ["Action: increment"])
    }
}
