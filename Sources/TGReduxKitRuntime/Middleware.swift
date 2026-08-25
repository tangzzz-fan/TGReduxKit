import TGReduxKitCore

/// Middleware intercepts an action and returns an `Effect`.
/// `Store` executes the effect; middleware must not own `Task`s directly.
public typealias Middleware<State, Action> = @MainActor (
    any StoreType<State, Action>,
    Action,
    @escaping @MainActor (Action) -> Effect<Action>
) -> Effect<Action>
