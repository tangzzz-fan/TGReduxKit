import Testing
import Foundation
import SwiftUI
@testable import TGReduxKit

struct TGReduxKitTests {
    @MainActor
    final class CountingScopeObserver: ScopeObserver {
        private(set) var refreshCount = 0

        func refreshStateFromParent() {
            refreshCount += 1
        }
    }

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

    let reducer: Reducer<TestState, TestAction> = { state, action in
        switch action {
        case .increment:
            state.count += 1
        case .decrement:
            state.count -= 1
        case .setMessage(let message):
            state.lastAction = message
        }
    }

    let rootReducer: Reducer<RootState, RootAction> = { state, action in
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
    @Test func testKeyPathBindingOnStoreReadsAndDispatches() {
        struct BindingState: Equatable {
            var name = ""
        }

        enum BindingAction: Equatable {
            case setName(String)
        }

        let bindingReducer: Reducer<BindingState, BindingAction> = { state, action in
            switch action {
            case .setName(let name):
                state.name = name
            }
        }

        let store = Store(initialState: BindingState(), reducer: bindingReducer)
        let binding = store.binding(get: \.name, send: BindingAction.setName)

        #expect(binding.wrappedValue == "")

        binding.wrappedValue = "Taylor"

        #expect(store.state.name == "Taylor")
        #expect(binding.wrappedValue == "Taylor")
    }

    @MainActor
    @Test func testKeyPathBindingOnScopedStoreReadsAndDispatches() {
        struct BindingFeatureState: Equatable {
            var name = ""
        }

        struct BindingRootState: Equatable {
            var feature = BindingFeatureState()
        }

        enum BindingFeatureAction: Equatable {
            case setName(String)
        }

        enum BindingRootAction: Equatable {
            case feature(BindingFeatureAction)
        }

        let bindingRootReducer: Reducer<BindingRootState, BindingRootAction> = { state, action in
            switch action {
            case .feature(.setName(let name)):
                state.feature.name = name
            }
        }

        let store = Store(initialState: BindingRootState(), reducer: bindingRootReducer)
        let featureStore = store.scope(state: \.feature, action: BindingRootAction.feature)
        let binding = featureStore.binding(get: \.name, send: BindingFeatureAction.setName)

        binding.wrappedValue = "Scoped"

        #expect(featureStore.state.name == "Scoped")
        #expect(store.state.feature.name == "Scoped")
    }

    @MainActor
    @Test func testAsyncActionInMiddleware() async throws {
        let asyncMiddleware: Middleware<TestState, TestAction> = { store, action, next in
            if case .increment = action {
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    store.dispatch(.setMessage("Async Done"))
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

        let nestedReducer: Reducer<NestedRootState, NestedRootAction> = { state, action in
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
    @Test func testEquatableNoOpDispatchDoesNotNotifyChildObservers() {
        struct StableState: Equatable {
            var count = 0
        }

        enum StableAction {
            case noop
        }

        let reducer: Reducer<StableState, StableAction> = { _, _ in }
        let store = Store(initialState: StableState(), reducer: reducer)
        let observer = CountingScopeObserver()

        _ = store.addChildObserver(observer)
        store.dispatch(.noop)

        #expect(observer.refreshCount == 0)
    }

    @MainActor
    @Test func testNonEquatableNoOpDispatchStillNotifiesChildObservers() {
        struct NonEquatableState {
            var count = 0
        }

        enum StableAction {
            case noop
        }

        let reducer: Reducer<NonEquatableState, StableAction> = { _, _ in }
        let store = Store(initialState: NonEquatableState(), reducer: reducer)
        let observer = CountingScopeObserver()

        _ = store.addChildObserver(observer)
        store.dispatch(.noop)

        #expect(observer.refreshCount == 1)
    }

    @MainActor
    @Test func testScopedStoreSkipsNoOpRefreshForEquatableState() {
        struct StableState: Equatable {
            var count = 0
        }

        enum StableAction {
            case noop
        }

        let store = ScopedStore<StableState, StableAction>(
            initialState: StableState(),
            dispatch: { _ in },
            stateProvider: { StableState() }
        )
        let observer = CountingScopeObserver()

        _ = store.addChildObserver(observer)
        store.refreshStateFromParent()

        #expect(observer.refreshCount == 0)
    }

    @MainActor
    @Test func testRunTaskCancelsPreviousTaskWithSameID() async throws {
        struct TaskState: Equatable {
            var values: [String] = []
        }

        enum TaskAction: Equatable {
            case append(String)
        }

        let taskReducer: Reducer<TaskState, TaskAction> = { state, action in
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
    @Test func testRunTaskWaitsForCancelledTaskToFinishBeforeReplacement() async throws {
        struct TaskState: Equatable {
            var values: [String] = []
        }

        enum TaskAction: Equatable {
            case append(String)
        }

        actor TaskLog {
            var events: [String] = []

            func append(_ event: String) {
                events.append(event)
            }

            func snapshot() -> [String] {
                events
            }
        }

        let taskReducer: Reducer<TaskState, TaskAction> = { state, action in
            switch action {
            case .append(let value):
                state.values.append(value)
            }
        }

        let log = TaskLog()
        let store = Store(initialState: TaskState(), reducer: taskReducer)

        store.runTask(id: "serialize") { [store] in
            await log.append("first-start")
            try? await Task.sleep(nanoseconds: 120_000_000)
            await log.append("first-end")
            await store.dispatch(.append("first"))
        }

        try? await Task.sleep(nanoseconds: 10_000_000)

        store.runTask(id: "serialize") { [store] in
            await log.append("second-start")
            await store.dispatch(.append("second"))
        }

        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(await log.snapshot() == ["first-start", "first-end", "second-start"])
        #expect(store.state.values == ["first", "second"])
    }

    @MainActor
    @Test func testCancellingReturnedTaskCleansUpManagedEntry() async throws {
        struct TaskState: Equatable {
            var values: [String] = []
        }

        enum TaskAction: Equatable {
            case append(String)
        }

        let taskReducer: Reducer<TaskState, TaskAction> = { state, action in
            switch action {
            case .append(let value):
                state.values.append(value)
            }
        }

        let store = Store(initialState: TaskState(), reducer: taskReducer)

        let task = store.runTask(id: "cancel-handle") {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        task.cancel()
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(!store.hasManagedTask(id: "cancel-handle"))
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
