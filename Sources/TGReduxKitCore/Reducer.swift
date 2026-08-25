import Foundation

/// A pure domain reducer. Nonisolated by construction — never bind to a global actor.
public struct Reducer<State: Sendable, Action: Sendable>: Sendable {
    public let reduce: @Sendable (inout State, Action, DependencyContext) -> Effect<Action>

    public init(
        _ reduce: @escaping @Sendable (inout State, Action, DependencyContext) -> Effect<Action>
    ) {
        self.reduce = reduce
    }

    /// Convenience for reducers that ignore dependencies.
    public init(
        _ reduce: @escaping @Sendable (inout State, Action) -> Effect<Action>
    ) {
        self.reduce = { state, action, _ in reduce(&state, action) }
    }

    /// State-only reducer with no effects.
    public static func sync(
        _ reduce: @escaping @Sendable (inout State, Action) -> Void
    ) -> Reducer {
        Reducer { state, action, _ in
            reduce(&state, action)
            return .none
        }
    }

    public func callAsFunction(
        _ state: inout State,
        _ action: Action,
        _ dependencies: DependencyContext = .live
    ) -> Effect<Action> {
        reduce(&state, action, dependencies)
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
    Reducer { state, action, dependencies in
        var effects: [Effect<Action>] = []
        effects.reserveCapacity(reducers.count)
        for reducer in reducers {
            effects.append(reducer.reduce(&state, action, dependencies))
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
    Reducer { parentState, parentAction, dependencies in
        guard let childAction = extract(parentAction) else {
            return .none
        }
        let effect = child.reduce(&parentState[keyPath: keyPath], childAction, dependencies)
        return effect.map(embed)
    }
}
