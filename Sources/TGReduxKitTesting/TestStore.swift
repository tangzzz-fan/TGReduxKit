import Foundation
import TGReduxKitCore

/// Lightweight harness for pure reducers (Swift Testing / XCTest friendly).
public final class TestStore<State: Equatable & Sendable, Action: Sendable>: @unchecked Sendable {
    public private(set) var state: State
    private let reducer: Reducer<State, Action>

    public init(initialState: State, reducer: @escaping Reducer<State, Action>) {
        self.state = initialState
        self.reducer = reducer
    }

    public func send(_ action: Action) {
        reducer(&state, action)
    }

    public func assert(
        equals expected: State,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard state == expected else {
            throw TestStoreAssertionError(
                message: "TestStore state mismatch.\n  Source: \(file):\(line)",
                state: state
            )
        }
    }

    public func assert(
        _ predicate: (State) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard predicate(state) else {
            throw TestStoreAssertionError(
                message: "TestStore assertion failed — state did not satisfy predicate.",
                state: state
            )
        }
    }
}

public struct TestStoreAssertionError<State>: Error, CustomStringConvertible, @unchecked Sendable {
    public let message: String
    public let state: State

    public var description: String {
        "\(message) (state: \(state))"
    }
}
