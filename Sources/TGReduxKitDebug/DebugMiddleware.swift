import Foundation
import TGReduxKitCore
import TGReduxKitRuntime

public func actionLoggingMiddleware<State: TGReduxKitCore.State, Action: TGReduxKitCore.Action>(
    logger: @escaping @Sendable (String) -> Void = { print($0) }
) -> Middleware<State, Action> {
    { _, action, next in
        logger("[Action] \(String(describing: action))")
        return next(action)
    }
}

public func stateDiffMiddleware<State: TGReduxKitCore.State, Action: TGReduxKitCore.Action>(
    logger: @escaping @Sendable (String) -> Void = { print($0) }
) -> Middleware<State, Action> {
    { store, action, next in
        let before = store.state
        let effect = next(action)
        let after = store.state
        if before != after {
            logger("""
            [State Diff] Action: \(String(describing: action))
            Before: \(before)
            After:  \(after)
            """)
        }
        return effect
    }
}

/// Materializes error info onto an action for reporting middleware.
public protocol ErrorAction: Sendable {
    var error: any Error & Sendable { get }
    var source: String { get }
}

/// Intercepts error-bearing actions for logging / analytics (does not catch async throws).
public func errorReportingMiddleware<State: TGReduxKitCore.State, Action: TGReduxKitCore.Action>(
    extract: @escaping @Sendable (Action) -> (error: any Error & Sendable, source: String)?,
    reporter: @escaping @Sendable (any Error & Sendable, String) -> Void
) -> Middleware<State, Action> {
    { _, action, next in
        let effect = next(action)
        if let (error, source) = extract(action) {
            reporter(error, source)
        }
        return effect
    }
}
