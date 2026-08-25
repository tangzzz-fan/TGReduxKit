import Foundation

/// Pure function. Zero actor binding.
/// Invoked by `Store` on `@MainActor`, but the reducer itself is isolation-agnostic.
public typealias Reducer<State, Action> = @Sendable (inout State, Action) -> Void

/// Runs reducers left-to-right.
public func combineReducers<State, Action>(
    _ reducers: Reducer<State, Action>...
) -> Reducer<State, Action> {
    combineReducers(Array(reducers))
}

public func combineReducers<State, Action>(
    _ reducers: [Reducer<State, Action>]
) -> Reducer<State, Action> {
    { state, action in
        for reducer in reducers {
            reducer(&state, action)
        }
    }
}

/// Lifts a child reducer into a parent state/action pair.
public func pullback<
    ChildState,
    ChildAction,
    ParentState,
    ParentAction
>(
    _ child: @escaping Reducer<ChildState, ChildAction>,
    state keyPath: WritableKeyPath<ParentState, ChildState> & Sendable,
    action embed: @escaping @Sendable (ChildAction) -> ParentAction,
    extract: @escaping @Sendable (ParentAction) -> ChildAction?
) -> Reducer<ParentState, ParentAction> {
    { parentState, parentAction in
        guard let childAction = extract(parentAction) else { return }
        child(&parentState[keyPath: keyPath], childAction)
    }
}
