import Foundation

/// A pure function that evolves the application state based on an action.
///
/// A `Reducer` takes the current state (as an `inout` parameter) and an action,
/// and updates the state synchronously. It should be a pure function without side effects.
///
/// - Parameters:
///   - state: The current state to be modified.
///   - action: The action that triggered the state change.
///
/// ## Example
///
/// ```swift
/// let counterReducer: Reducer<Int, Action> = { state, action in
///     switch action {
///     case .increment: state += 1
///     case .decrement: state -= 1
///     }
/// }
/// ```
public typealias Reducer<State, Action> = (inout State, Action) -> Void
