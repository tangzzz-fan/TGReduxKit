import Foundation

/// A domain reducer. Nonisolated — never bind to a global actor.
/// Dependencies are captured in the factory (`@Sendable` closures), not injected each reduce.
public struct Reducer<State: Sendable, Action: Sendable>: Sendable {
    public let reduce: @Sendable (inout State, Action) -> Effect<Action>

    public init(
        _ reduce: @escaping @Sendable (inout State, Action) -> Effect<Action>
    ) {
        self.reduce = reduce
    }

    /// State-only reducer with no effects.
    public static func sync(
        _ reduce: @escaping @Sendable (inout State, Action) -> Void
    ) -> Reducer {
        Reducer { state, action in
            reduce(&state, action)
            return .none
        }
    }

    public func callAsFunction(
        _ state: inout State,
        _ action: Action
    ) -> Effect<Action> {
        reduce(&state, action)
    }
}

/// Runs reducers left-to-right and merges their effects.
public func combineReducers<State: Sendable, Action: Sendable>(
    _ reducers: Reducer<State, Action>...
) -> Reducer<State, Action> {
    combineReducers(Array(reducers))
}

public func combineReducers<State: Sendable, Action: Sendable>(
    _ reducers: [Reducer<State, Action>]
) -> Reducer<State, Action> {
    Reducer { state, action in
        var effects: [Effect<Action>] = []
        effects.reserveCapacity(reducers.count)
        for reducer in reducers {
            effects.append(reducer.reduce(&state, action))
        }
        return .merge(effects)
    }
}

/// Lifts a child reducer, embedding child follow-up actions into the parent.
public func pullback<
    ChildState: Sendable,
    ChildAction: Sendable,
    ParentState: Sendable,
    ParentAction: Sendable
>(
    _ child: Reducer<ChildState, ChildAction>,
    state keyPath: WritableKeyPath<ParentState, ChildState> & Sendable,
    action embed: @escaping @Sendable (ChildAction) -> ParentAction,
    extract: @escaping @Sendable (ParentAction) -> ChildAction?
) -> Reducer<ParentState, ParentAction> {
    Reducer { parentState, parentAction in
        guard let childAction = extract(parentAction) else {
            return .none
        }
        let effect = child.reduce(&parentState[keyPath: keyPath], childAction)
        return effect.map(embed)
    }
}
