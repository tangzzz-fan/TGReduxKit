import Foundation

public func actionLoggingMiddleware<State, Action>(
    logger: @escaping @Sendable (String) -> Void = { message in
        print(message)
    }
) -> Middleware<State, Action> {
    { _, action, next in
        logger("Action: \(String(describing: action))")
        next(action)
    }
}

public func stateDiffMiddleware<State, Action>(
    logger: @escaping @Sendable (String) -> Void = { message in
        print(message)
    }
) -> Middleware<State, Action> {
    { store, action, next in
        let before = String(describing: store.state)
        next(action)
        let after = String(describing: store.state)
        logger(
            """
            Action: \(String(describing: action))
            Before: \(before)
            After: \(after)
            """
        )
    }
}
