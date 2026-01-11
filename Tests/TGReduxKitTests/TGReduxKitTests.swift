import Testing
import Foundation
@testable import TGReduxKit

struct TGReduxKitTests {
    
    struct TestState: Equatable {
        var count: Int = 0
        var lastAction: String = ""
    }
    
    enum TestAction: Equatable {
        case increment
        case decrement
        case setMessage(String)
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

    @Test func testStoreInitialization() {
        let store = Store(initialState: TestState(), reducer: reducer)
        #expect(store.state == TestState(count: 0, lastAction: ""))
    }
    
    @Test func testDispatch() {
        let store = Store(initialState: TestState(), reducer: reducer)
        
        store.dispatch(.increment)
        #expect(store.state.count == 1)
        
        store.dispatch(.decrement)
        #expect(store.state.count == 0)
        
        store.dispatch(.setMessage("Hello"))
        #expect(store.state.lastAction == "Hello")
    }
    
    @Test func testMiddleware() {
        var middlewareLog: [String] = []
        
        let loggingMiddleware: Middleware<TestState, TestAction> = { store, action, next in
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
    
    @Test func testMiddlewareChaining() {
        var log: [String] = []
        
        let m1: Middleware<TestState, TestAction> = { _, _, next in
            log.append("M1 Pre")
            next(.increment) // Pass the action
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
        
        // M1 Pre -> M2 Pre -> Reducer -> M2 Post -> M1 Post
        #expect(log == ["M1 Pre", "M2 Pre", "M2 Post", "M1 Post"])
        #expect(store.state.count == 1)
    }
    
    @Test func testAsyncActionInMiddleware() async throws {
        // Since Middleware itself is synchronous in signature (but can launch Tasks),
        // we test if we can dispatch from within a Task in middleware.
        
        let asyncMiddleware: Middleware<TestState, TestAction> = { store, action, next in
            if case .increment = action {
                Task {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    // Store is now @unchecked Sendable, so we can capture it safely.
                    // However, to be strictly correct with Swift 6, we should capture it.
                    // But `store` is a class, so it's reference semantic.
                    // The warning was likely about `store` being non-Sendable.
                    // Now that Store is @unchecked Sendable, this should be fine.
                    await MainActor.run {
                        store.dispatch(.setMessage("Async Done"))
                    }
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
        
        try await Task.sleep(nanoseconds: 200_000_000) // Wait for async
        #expect(store.state.lastAction == "Async Done")
    }
}
