import Foundation
import TGReduxKitCore
import TGReduxKitRuntime

/// Deterministic test harness for reducers and effects.
public final class TestStore<State: Equatable & Sendable, Action: Sendable>: @unchecked Sendable {
    public private(set) var state: State
    public private(set) var recordedEffects: [Effect<Action>] = []

    private let reducer: Reducer<State, Action>

    public init(
        initialState: State,
        reducer: Reducer<State, Action>
    ) {
        self.state = initialState
        self.reducer = reducer
    }

    /// Applies the reducer synchronously and records the returned effect without running it.
    @discardableResult
    public func send(_ action: Action) -> Effect<Action> {
        let effect = reducer.reduce(&state, action)
        recordedEffects.append(effect)
        return effect
    }

    public func assert(
        _ predicate: (State) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard predicate(state) else {
            throw TestStoreAssertionError(
                message: "TestStore assertion failed — state did not satisfy predicate.",
                state: state,
                file: file,
                line: line
            )
        }
    }

    public func assert(
        equals expected: State,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard state == expected else {
            throw TestStoreAssertionError(
                message: "TestStore state mismatch.\n  Source: \(file):\(line)",
                state: state,
                file: file,
                line: line
            )
        }
    }

    /// Runs recorded effects on a live `@MainActor` store, then syncs state back.
    @MainActor
    public func runEffects() async -> State {
        let store = Store(initialState: state, reducer: reducer)
        let pending = recordedEffects
        recordedEffects.removeAll()
        for effect in pending {
            await runEffect(effect, on: store)
        }
        state = store.state
        return state
    }

    @MainActor
    private func runEffect(_ effect: Effect<Action>, on store: Store<State, Action>) async {
        switch effect.operation {
        case .none:
            return
        case .cancel:
            return
        case .merge(let effects):
            for child in effects {
                await runEffect(child, on: store)
            }
        case .run(_, let work):
            let send = Send<Action> { action in
                await MainActor.run {
                    _ = store.dispatch(action)
                }
            }
            do {
                try await work(send)
            } catch {
                return
            }
        }
    }
}

public struct TestStoreAssertionError<State>: Error, CustomStringConvertible, @unchecked Sendable {
    public let message: String
    public let state: State
    public let file: StaticString
    public let line: UInt

    public var description: String {
        "\(message) (state: \(state), at \(file):\(line))"
    }
}
