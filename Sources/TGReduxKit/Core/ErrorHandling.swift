import Foundation

// MARK: - ErrorAction

/// A protocol for actions that carry error information.
///
/// Conform your error-bearing action cases to this protocol so that
/// `store.runTask(catching:)` and `errorReportingMiddleware` can
/// route errors into the Redux state flow.
///
/// ## Example
///
/// ```swift
/// enum AppAction: Equatable {
///     case dataLoaded(Data)
///     case loadFailed(Error, source: String)
/// }
///
/// // Add a computed property or nested type that conforms to ErrorAction:
/// extension AppAction {
///     struct LoadError: ErrorAction, Equatable {
///         let error: Error
///         let source: String
///     }
/// }
/// ```
public protocol ErrorAction {
    /// The underlying error.
    var error: Error { get }

    /// A human-readable label identifying where the error originated
    /// (e.g. `"userProfile"`, `"search"`).
    var source: String { get }
}

// MARK: - Error reporting middleware

/// Creates a middleware that intercepts actions and forwards errors to the
/// provided reporter closure when the `extract` closure returns a non-nil
/// `(Error, source)` pair.
///
/// This is useful for centralised logging, crash reporting, or analytics.
///
/// ## Example
///
/// ```swift
/// let errorMiddleware = errorReportingMiddleware { action in
///     if case .loadFailed(let error, let source) = action {
///         return (error, source)
///     }
///     return nil
/// } reporter: { error, source in
///     CrashReporter.record(error, source: source)
/// }
/// ```
///
/// For actions that conform to `ErrorAction`, use the convenience overload
/// that auto-detects conformance:
///
/// ```swift
/// let store = Store(
///     initialState: AppState(),
///     reducer: appReducer,
///     middlewares: [
///         errorReportingMiddleware(reporter: { error, source in
///             CrashReporter.record(error, source: source)
///         })
///     ]
/// )
/// ```
public func errorReportingMiddleware<State, Action>(
    extract: @escaping @Sendable (Action) -> (error: Error, source: String)?,
    reporter: @escaping @Sendable (Error, String) -> Void
) -> Middleware<State, Action> {
    { _, action, next in
        next(action)

        if let extracted = extract(action) {
            reporter(extracted.error, extracted.source)
        }
    }
}

/// Convenience overload that extracts errors from actions conforming to `ErrorAction`.
///
/// Only works when the `Action` type itself conforms to `ErrorAction` — useful when
/// your action is a dedicated error struct rather than a large enum.
public func errorReportingMiddleware<State, Action: ErrorAction>(
    reporter: @escaping @Sendable (Error, String) -> Void
) -> Middleware<State, Action> {
    { _, action, next in
        next(action)

        reporter(action.error, action.source)
    }
}

// MARK: - runTask with error catching

extension Store {
    /// Runs an asynchronous throwing operation, converting thrown errors into actions
    /// via the `catching` closure.
    ///
    /// When `operation` throws, the `catching` closure produces an action that is
    /// dispatched to the store. If `catching` returns `nil` the error is silently dropped.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for the task (supports cancellation).
    ///   - catching: A closure that maps a thrown error to an optional action.
    ///   - priority: The task priority.
    ///   - operation: The throwing async operation to execute.
    ///
    /// ## Example
    ///
    /// ```swift
    /// store.runTask(id: "load-user", catching: { error in
    ///     .loadFailed(error, source: "userProfile")
    /// }) {
    ///     let user = try await userRepository.fetchUser()
    ///     await store.dispatch(.userLoaded(user))
    /// }
    /// ```
    @discardableResult
    public func runTask(
        id: CancellationID? = nil,
        catching: @escaping @Sendable (Error) -> Action?,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Task<Void, Never> {
        let store = self
        return runTask(id: id, priority: priority) {
            do {
                try await operation()
            } catch {
                guard !Task.isCancelled else { return }

                if let action = catching(error) {
                    await store.dispatch(action)
                }
            }
        }
    }
}
