import Foundation
import Observation

/// The main state container for the application, following the Redux pattern.
///
/// `Store` holds the single source of truth (`State`) for your application.
/// It uses the `@Observable` macro to automatically notify SwiftUI views when the state changes.
///
/// ## Usage Example
///
/// ```swift
/// // 1. Define State
/// struct AppState {
///     var count = 0
/// }
///
/// // 2. Define Action
/// enum AppAction {
///     case increment
///     case decrement
/// }
///
/// // 3. Define Reducer
/// let appReducer: Reducer<AppState, AppAction> = { state, action in
///     switch action {
///     case .increment: state.count += 1
///     case .decrement: state.count -= 1
///     }
/// }
///
/// // 4. Initialize Store
/// let store = Store(initialState: AppState(), reducer: appReducer)
///
/// // 5. Dispatch Action
/// store.dispatch(.increment)
/// ```
@Observable
public final class Store<State, Action>: @unchecked Sendable {
    /// The current state of the application.
    ///
    /// This property is read-only. To modify the state, you must dispatch an action.
    /// SwiftUI views accessing this property will automatically update when it changes.
    public private(set) var state: State
    
    private let reducer: Reducer<State, Action>
    private let middlewares: [Middleware<State, Action>]
    private let lock = NSLock()

    /// Initializes a new Store.
    ///
    /// - Parameters:
    ///   - initialState: The initial value of the state.
    ///   - reducer: A pure function that evolves the state based on actions.
    ///   - middlewares: An optional list of middlewares to handle side effects.
    public init(
        initialState: State,
        reducer: @escaping Reducer<State, Action>,
        middlewares: [Middleware<State, Action>] = []
    ) {
        self.state = initialState
        self.reducer = reducer
        self.middlewares = middlewares
    }

    /// Dispatches an action to change the state.
    ///
    /// This is the only way to trigger a state change. The action will flow through
    /// the middleware chain before reaching the reducer.
    ///
    /// - Parameter action: The action describing what happened.
    public func dispatch(_ action: Action) {
        // Create the initial dispatch function that applies the reducer
        let initialDispatch: Dispatch<Action> = { [weak self] action in
            guard let self = self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            self.reducer(&self.state, action)
        }
        
        // Chain middlewares
        let dispatchFunction = middlewares.reversed().reduce(initialDispatch) { nextDispatch, middleware in
            return { [weak self] action in
                guard let self = self else { return }
                middleware(self, action, nextDispatch)
            }
        }
        
        dispatchFunction(action)
    }
}
