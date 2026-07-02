import Foundation

/// A test harness for synchronously testing reducer logic.
///
/// `TestStore` provides a lightweight way to verify reducer behavior by dispatching
/// actions and asserting expected state transitions. It is designed for pure reducer
/// testing and does not involve middleware or side effects.
///
/// ## Usage
///
/// ```swift
/// @Test func counterFlow() {
///     let store = TestStore(initialState: CounterState(), reducer: counterReducer)
///
///     store.send(.increment)
///     store.assert(equals: CounterState(count: 1))
///
///     store.send(.increment, expect: CounterState(count: 2))
///     store.send(.decrement)
///     store.assert(equals: CounterState(count: 1))
/// }
/// ```
@MainActor
public final class TestStore<State: Equatable, Action> {
    /// The current state after all dispatched actions.
    public private(set) var state: State

    /// Complete history of states, recorded after each `send(_:)`.
    /// The initial state is included at index 0.
    public private(set) var stateHistory: [State]

    private let reducer: Reducer<State, Action>

    /// Creates a new TestStore with the given initial state and reducer.
    ///
    /// - Parameters:
    ///   - initialState: The starting state for the test.
    ///   - reducer: The reducer to test.
    public init(initialState: State, reducer: @escaping Reducer<State, Action>) {
        self.state = initialState
        self.stateHistory = [initialState]
        self.reducer = reducer
    }

    /// Dispatches an action to the reducer and returns the new state.
    ///
    /// The state history is automatically recorded after each send.
    ///
    /// - Parameter action: The action to dispatch.
    /// - Returns: The state after the reducer has processed the action.
    @discardableResult
    public func send(_ action: Action) -> State {
        reducer(&state, action)
        stateHistory.append(state)
        return state
    }

    /// Dispatches an action and asserts the resulting state equals the expected value.
    ///
    /// This is a convenience combining `send(_:)` and `assert(equals:)`.
    ///
    /// - Parameters:
    ///   - action: The action to dispatch.
    ///   - expected: The expected state after the action is processed.
    ///   - file: The file where the assertion originates (automatically filled).
    ///   - line: The line where the assertion originates (automatically filled).
    @discardableResult
    public func send(
        _ action: Action,
        expect expected: State,
        file: StaticString = #file,
        line: UInt = #line
    ) -> State {
        let newState = send(action)
        assert(equals: expected, file: file, line: line)
        return newState
    }

    /// Asserts that the current state satisfies the given predicate.
    ///
    /// When the predicate returns `false`, the assertion fails with an optional message
    /// and the current state is included in the failure description.
    ///
    /// - Parameters:
    ///   - message: An optional message describing the assertion.
    ///   - file: The file where the assertion originates (automatically filled).
    ///   - line: The line where the assertion originates (automatically filled).
    ///   - predicate: A closure that returns `true` if the state matches expectations.
    public func assert(
        _ message: String? = nil,
        file: StaticString = #file,
        line: UInt = #line,
        _ predicate: (State) -> Bool
    ) {
        if !predicate(state) {
            let baseMessage = "TestStore assertion failed — state did not satisfy predicate."
            let fullMessage = message.map { "\(baseMessage) \($0)" } ?? baseMessage
            // Use fatalError in test context to produce a clear failure
            fatalError("\(fullMessage)\n  Current state: \(state)", file: file, line: line)
        }
    }

    /// Asserts that the current state is equal to the expected state.
    ///
    /// When the states differ, the assertion fails with a detailed diff.
    ///
    /// - Parameters:
    ///   - expected: The expected state.
    ///   - file: The file where the assertion originates (automatically filled).
    ///   - line: The line where the assertion originates (automatically filled).
    public func assert(
        equals expected: State,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        if state != expected {
            fatalError(
                """
                TestStore state mismatch.
                  Expected: \(expected)
                  Actual:   \(state)
                """,
                file: file,
                line: line
            )
        }
    }

    /// Resets the TestStore to a new initial state, clearing all history.
    ///
    /// - Parameter initialState: The new starting state.
    public func reset(to initialState: State) {
        state = initialState
        stateHistory = [initialState]
    }

    /// Replays the recorded state history from an action sequence.
    ///
    /// This is useful when you want to inspect intermediate states in a multi-step flow.
    ///
    /// - Returns: The array of all recorded states (including the initial state).
    public func replayHistory() -> [State] {
        stateHistory
    }
}
