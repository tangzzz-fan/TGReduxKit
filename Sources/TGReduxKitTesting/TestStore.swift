import Foundation
import TGReduxKitCore
import TGReduxKitRuntime

/// Deterministic test harness for reducers and effects.
public final class TestStore<State: Equatable & Sendable, Action: Sendable>: @unchecked Sendable {
    public private(set) var state: State
    public private(set) var recordedEffects: [Effect<Action>] = []

    private let reducer: Reducer<State, Action>
    private var dependencies: DependencyContext

    public init(
        initialState: State,
        reducer: Reducer<State, Action>,
        dependencies: DependencyContext = .immediate
    ) {
        self.state = initialState
        self.reducer = reducer
        self.dependencies = dependencies
    }

    /// Applies the reducer synchronously and records the returned effect without running it.
    @discardableResult
    public func send(_ action: Action) -> Effect<Action> {
        let effect = reducer.reduce(&state, action, dependencies)
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

    /// Runs recorded effects against a live actor store starting from the current state.
    public func runEffects() async -> State {
        let store = Store(initialState: state, reducer: reducer, dependencies: dependencies)
        let pending = recordedEffects
        recordedEffects.removeAll()
        for effect in pending {
            // Drive by re-dispatching through a no-op action path is awkward;
            // instead temporarily expose run via dispatch of a synthetic path:
            // We apply effects by injecting them through Store's private API — use a helper reducer.
            _ = store
            await runEffect(effect, on: store)
        }
        return await store.currentState()
    }

    private func runEffect(_ effect: Effect<Action>, on store: Store<State, Action>) async {
        // Replay by wrapping: dispatch is the only public entry; use Effect.run merge via reducer bypass.
        // Install a one-shot by calling store with a pass-through: we duplicate Runtime scheduling lightly.
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
            do {
                if let action = try await work() {
                    _ = await store.dispatch(action)
                }
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
