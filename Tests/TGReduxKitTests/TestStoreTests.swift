import Testing
import Foundation
@testable import TGReduxKit

struct TestStoreTests {
    struct TestState: Equatable {
        var count: Int = 0
        var message: String = ""
        var items: [String] = []
    }

    enum TestAction: Equatable {
        case increment
        case decrement
        case setMessage(String)
        case addItem(String)
        case reset
    }

    let reducer: Reducer<TestState, TestAction> = { state, action in
        switch action {
        case .increment:
            state.count += 1
        case .decrement:
            state.count -= 1
        case .setMessage(let message):
            state.message = message
        case .addItem(let item):
            state.items.append(item)
        case .reset:
            state = TestState()
        }
    }

    // MARK: - Basic send

    @MainActor
    @Test func testSendReturnsNewState() {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        let newState = store.send(.increment)
        #expect(newState.count == 1)
    }

    @MainActor
    @Test func testSendUpdatesState() {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.increment)
        store.send(.increment)
        #expect(store.state.count == 2)

        store.send(.decrement)
        #expect(store.state.count == 1)
    }

    // MARK: - send with expect

    @MainActor
    @Test func testSendExpectPassesForMatchingState() throws {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        try store.send(.increment, expect: TestState(count: 1))
        try store.send(.setMessage("Hello"), expect: TestState(count: 1, message: "Hello"))
    }

    // MARK: - assert equals

    @MainActor
    @Test func testAssertEqualsPasses() throws {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.increment)
        try store.assert(equals: TestState(count: 1))

        store.send(.decrement)
        try store.assert(equals: TestState(count: 0))
    }

    @MainActor
    @Test func testMultiStepFlow() throws {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.increment)
        store.send(.increment)
        store.send(.setMessage("done"))
        try store.assert { state in
            state.count == 2 && state.message == "done"
        }
    }

    // MARK: - assert with predicate

    @MainActor
    @Test func testAssertPredicatePasses() throws {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.increment)
        try store.assert("count should be positive") { state in
            state.count > 0
        }
    }

    @MainActor
    @Test func testAssertPredicatePassesCompoundCondition() throws {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.addItem("A"))
        store.send(.addItem("B"))
        store.send(.addItem("C"))
        store.send(.increment)

        try store.assert { state in
            state.items.count == 3 && state.count == 1
        }
    }

    @MainActor
    @Test func testSendExpectThrowsStructuredErrorForMismatch() {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        var capturedError: TestStoreAssertionError<TestState>?

        do {
            try store.send(.increment, expect: TestState(count: 2))
        } catch let error as TestStoreAssertionError<TestState> {
            capturedError = error
        } catch {
            #expect(Bool(false))
        }

        #expect(capturedError != nil)
        #expect(capturedError?.expectedState == TestState(count: 2))
        #expect(capturedError?.currentState == TestState(count: 1))
        #expect(capturedError?.description.contains("TestStore state mismatch.") == true)
    }

    @MainActor
    @Test func testAssertPredicateThrowsStructuredErrorForFailure() {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        var capturedError: TestStoreAssertionError<TestState>?

        do {
            try store.assert("count should be positive") { state in
                state.count > 0
            }
        } catch let error as TestStoreAssertionError<TestState> {
            capturedError = error
        } catch {
            #expect(Bool(false))
        }

        #expect(capturedError != nil)
        #expect(capturedError?.currentState == TestState())
        #expect(capturedError?.description.contains("count should be positive") == true)
    }

    // MARK: - State history

    @MainActor
    @Test func testStateHistoryRecordsInitialState() {
        let store = TestStore(initialState: TestState(), reducer: reducer)
        #expect(store.stateHistory.count == 1)
        #expect(store.stateHistory[0] == TestState())
    }

    @MainActor
    @Test func testStateHistoryRecordsEachSend() {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.increment)
        store.send(.increment)
        store.send(.decrement)

        #expect(store.stateHistory.count == 4)
        #expect(store.stateHistory[0].count == 0)
        #expect(store.stateHistory[1].count == 1)
        #expect(store.stateHistory[2].count == 2)
        #expect(store.stateHistory[3].count == 1)
    }

    @MainActor
    @Test func testReplayHistoryReturnsFullHistory() {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.increment)
        store.send(.setMessage("test"))

        let history = store.replayHistory()
        #expect(history.count == 3)
        #expect(history[0] == TestState())
        #expect(history[1] == TestState(count: 1))
        #expect(history[2] == TestState(count: 1, message: "test"))
    }

    // MARK: - Reset

    @MainActor
    @Test func testResetClearsStateAndHistory() {
        let store = TestStore(initialState: TestState(), reducer: reducer)

        store.send(.increment)
        store.send(.setMessage("before reset"))
        #expect(store.stateHistory.count == 3)

        store.reset(to: TestState(count: 100))

        #expect(store.state.count == 100)
        #expect(store.stateHistory.count == 1)
        #expect(store.stateHistory[0].count == 100)
    }

    // MARK: - Complex scenario

    @MainActor
    @Test func testShoppingCartFlow() throws {
        struct CartState: Equatable {
            var items: [String] = []
            var total: Int = 0
        }

        enum CartAction: Equatable {
            case addItem(String, price: Int)
            case removeItem(String)
            case clear
        }

        let cartReducer: Reducer<CartState, CartAction> = { state, action in
            switch action {
            case .addItem(let name, let price):
                state.items.append(name)
                state.total += price
            case .removeItem(let name):
                state.items.removeAll { $0 == name }
            case .clear:
                state = CartState()
            }
        }

        let store = TestStore(initialState: CartState(), reducer: cartReducer)

        try store.send(.addItem("Widget", price: 10), expect: CartState(items: ["Widget"], total: 10))
        try store.send(.addItem("Gadget", price: 20), expect: CartState(items: ["Widget", "Gadget"], total: 30))
        store.send(.removeItem("Widget"))
        try store.assert { state in
            state.items == ["Gadget"] && state.total == 30
        }
        try store.send(.clear, expect: CartState())

        let history = store.replayHistory()
        #expect(history.count == 5)  // initial + 4 actions
    }

    // MARK: - Nested enum action patterns

    @MainActor
    @Test func testNestedEnumActionPattern() throws {
        struct ParentState: Equatable {
            var child = ChildState()
        }

        struct ChildState: Equatable {
            var value: Int = 0
            var enabled: Bool = false
        }

        enum ParentAction: Equatable {
            case child(ChildAction)
        }

        enum ChildAction: Equatable {
            case setValue(Int)
            case toggle
        }

        let parentReducer: Reducer<ParentState, ParentAction> = { state, action in
            switch action {
            case .child(let childAction):
                switch childAction {
                case .setValue(let v):
                    state.child.value = v
                case .toggle:
                    state.child.enabled.toggle()
                }
            }
        }

        let store = TestStore(initialState: ParentState(), reducer: parentReducer)

        store.send(.child(.setValue(42)))
        #expect(store.state.child.value == 42)

        try store.send(.child(.toggle), expect: ParentState(child: ChildState(value: 42, enabled: true)))

        store.send(.child(.setValue(0)))
        try store.send(.child(.toggle), expect: ParentState(child: ChildState(value: 0, enabled: false)))
    }
}
