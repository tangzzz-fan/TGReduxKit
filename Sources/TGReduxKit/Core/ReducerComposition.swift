import Foundation

// MARK: - combineReducers

/// Combines multiple reducers into a single reducer that executes each in order.
///
/// Each reducer is invoked for every action. This means side-effect-free reducers
/// can safely coexist — each reducer independently decides whether to respond to
/// a given action.
///
/// When combined with ``pullback(_:state:extract:)``, each child reducer
/// receives the action only when the extractor returns a non-nil child action,
/// effectively creating a type-safe routing table.
///
/// ## Example
///
/// ```swift
/// let appReducer = combineReducers(
///     pullback(catalogReducer, state: \.catalog, extract: {
///         if case .catalog(let a) = $0 { a } else { nil }
///     }),
///     pullback(cartReducer, state: \.cart, extract: {
///         if case .cart(let a) = $0 { a } else { nil }
///     })
/// )
/// ```
///
/// - Parameter reducers: A variadic list of reducers to combine.
/// - Returns: A single reducer that executes each child reducer in order.
public func combineReducers<State, Action>(
    _ reducers: Reducer<State, Action>...
) -> Reducer<State, Action> {
    { state, action in
        for reducer in reducers {
            reducer(&state, action)
        }
    }
}

// MARK: - pullback

/// Lifts a child reducer to operate on a parent state and action space.
///
/// The returned reducer only executes when `extract` returns a non-nil child
/// action from the parent action. This makes it safe to combine multiple
/// pullback-reducers with ``combineReducers(_:)`` — each one self-identifies
/// whether it should handle the dispatched action.
///
/// - Parameters:
///   - reducer: The child reducer to lift.
///   - state: A writable key path from parent state to child state.
///   - extract: A closure that attempts to extract a child action from a parent action.
///              Returns `nil` when the action does not belong to this child.
/// - Returns: A reducer that operates on the parent state and action types.
///
/// ## Example
///
/// ```swift
/// let catalogReducer: Reducer<CatalogState, CatalogAction> = ...
///
/// let liftedReducer = pullback(
///     catalogReducer,
///     state: \AppState.catalog,
///     extract: { parentAction in
///         if case .catalog(let childAction) = parentAction {
///             return childAction
///         }
///         return nil
///     }
/// )
/// // liftedReducer is now Reducer<AppState, AppAction>
/// ```
public func pullback<ChildState, ChildAction, ParentState, ParentAction>(
    _ reducer: @escaping Reducer<ChildState, ChildAction>,
    state: WritableKeyPath<ParentState, ChildState>,
    extract: @escaping (ParentAction) -> ChildAction?
) -> Reducer<ParentState, ParentAction> {
    return { parentState, parentAction in
        guard let childAction = extract(parentAction) else { return }
        var childState = parentState[keyPath: state]
        reducer(&childState, childAction)
        parentState[keyPath: state] = childState
    }
}
