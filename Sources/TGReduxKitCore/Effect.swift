import Foundation

/// A handle for emitting one or more follow-up actions from an effect.
public struct Send<Action: Sendable>: Sendable {
    private let handler: @Sendable (Action) async -> Void

    public init(_ handler: @escaping @Sendable (Action) async -> Void) {
        self.handler = handler
    }

    public func callAsFunction(_ action: Action) async {
        await handler(action)
    }
}

/// Declarative side effect. Supports multi-value emission via `Send` (TCA-style).
public struct Effect<Action: Sendable>: Sendable {
    public enum Operation: Sendable {
        case none
        case run(id: CancellationID?, work: @Sendable (Send<Action>) async throws -> Void)
        case cancel(CancellationID)
        case merge([Effect<Action>])
    }

    public let operation: Operation

    public init(operation: Operation) {
        self.operation = operation
    }

    public static var none: Effect {
        Effect(operation: .none)
    }

    /// Multi-value effect. Call `send` zero or more times.
    public static func run(
        id: CancellationID? = nil,
        _ work: @escaping @Sendable (Send<Action>) async throws -> Void
    ) -> Effect {
        Effect(operation: .run(id: id, work: work))
    }

    /// Single follow-up convenience (wraps `Send`).
    public static func run(
        id: CancellationID? = nil,
        producing work: @escaping @Sendable () async throws -> Action
    ) -> Effect {
        .run(id: id) { send in
            await send(try await work())
        }
    }

    /// Optional single follow-up.
    public static func runOptional(
        id: CancellationID? = nil,
        _ work: @escaping @Sendable () async throws -> Action?
    ) -> Effect {
        .run(id: id) { send in
            if let action = try await work() {
                await send(action)
            }
        }
    }

    public static func cancel(id: CancellationID) -> Effect {
        Effect(operation: .cancel(id))
    }

    public static func merge(_ effects: [Effect<Action>]) -> Effect {
        let flattened = effects.filter { effect in
            if case .none = effect.operation { return false }
            return true
        }
        if flattened.isEmpty { return .none }
        if flattened.count == 1 { return flattened[0] }
        return Effect(operation: .merge(flattened))
    }

    public static func merge(_ effects: Effect<Action>...) -> Effect {
        merge(effects)
    }

    public func cancellable(id: CancellationID) -> Effect {
        switch operation {
        case .none, .cancel:
            return self
        case .run(_, let work):
            return Effect(operation: .run(id: id, work: work))
        case .merge(let effects):
            return .merge(effects.map { $0.cancellable(id: id) })
        }
    }

    public func debounce(for duration: Duration) -> Effect {
        switch operation {
        case .none, .cancel:
            return self
        case .run(let id, let work):
            return Effect(operation: .run(id: id, work: { send in
                try await Task.sleep(for: duration)
                try Task.checkCancellation()
                try await work(send)
            }))
        case .merge(let effects):
            return .merge(effects.map { $0.debounce(for: duration) })
        }
    }

    public func throttle(for duration: Duration) -> Effect {
        switch operation {
        case .none, .cancel:
            return self
        case .run(let id, let work):
            return Effect(operation: .run(id: id, work: { send in
                try await work(send)
                try await Task.sleep(for: duration)
                try Task.checkCancellation()
            }))
        case .merge(let effects):
            return .merge(effects.map { $0.throttle(for: duration) })
        }
    }

    public func map<NewAction: Sendable>(
        _ transform: @escaping @Sendable (Action) -> NewAction
    ) -> Effect<NewAction> {
        switch operation {
        case .none:
            return .none
        case .cancel(let id):
            return .cancel(id: id)
        case .run(let id, let work):
            return Effect<NewAction>(operation: .run(id: id, work: { send in
                let mapped = Send<Action> { action in
                    await send(transform(action))
                }
                try await work(mapped)
            }))
        case .merge(let effects):
            return .merge(effects.map { $0.map(transform) })
        }
    }
}
