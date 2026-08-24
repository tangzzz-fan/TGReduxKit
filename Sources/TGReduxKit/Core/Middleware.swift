import Foundation

/// A function used to dispatch an action.
public typealias ActionDispatcher<Action> = @MainActor (Action) -> Void

/// A function that intercepts actions before they reach the reducer.
///
/// Middleware is the recommended place for side effects, such as API calls, logging, or analytics.
/// Middleware itself runs on the main actor so state reads and action forwarding stay serialized.
/// Long-running async work should escape via `Task` or `store.runTask(...)`, then re-enter the
/// state flow by dispatching a follow-up action.
///
/// - Parameters:
///   - store: The store instance (can be used to read state or dispatch new actions).
///   - action: The action being dispatched.
///   - next: A function to call to pass the action to the next middleware (or the reducer).
///
/// ## Example: Logging Middleware
///
/// ```swift
/// let loggingMiddleware: Middleware<AppState, AppAction> = { store, action, next in
///     print("Action dispatched: \(action)")
///     next(action) // Pass to next middleware/reducer
///     print("New state: \(store.state)")
/// }
/// ```
///
/// ## Example: Async/Side Effect Middleware
///
/// ```swift
/// let apiMiddleware: Middleware<AppState, AppAction> = { store, action, next in
///     next(action) // Update state first if needed
///
///     if case .fetchUser = action {
///         store.runTask(id: "fetch-user") {
///             let user = await fetchUserFromAPI()
///             await store.dispatch(.userLoaded(user))
///         }
///     }
/// }
/// ```
public typealias Middleware<State, Action> = @MainActor (Store<State, Action>, Action, @escaping ActionDispatcher<Action>) -> Void
