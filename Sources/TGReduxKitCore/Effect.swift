import Foundation

/// A declarative asynchronous side effect that may produce a follow-up action.
public struct Effect<Action: Sendable>: Sendable {
    public enum Operation: Sendable {
        case none
        case run(id: CancellationID?, work: @Sendable () async throws -> Action?)
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

    public static func run(
        id: CancellationID? = nil,
        _ work: @escaping @Sendable () async throws -> Action
    ) -> Effect {
        Effect(operation: .run(id: id, work: { try await work() }))
    }

    public static func runOptional(
        id: CancellationID? = nil,
        _ work: @escaping @Sendable () async throws -> Action?
    ) -> Effect {
        Effect(operation: .run(id: id, work: work))
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

    /// Delays starting the underlying work. Uses `Task.sleep`.
    public func debounce(for duration: Duration) -> Effect {
        switch operation {
        case .none, .cancel:
            return self
        case .run(let id, let work):
            return Effect(operation: .run(id: id, work: {
                try await Task.sleep(for: duration)
                try Task.checkCancellation()
                return try await work()
            }))
        case .merge(let effects):
            return .merge(effects.map { $0.debounce(for: duration) })
        }
    }

    /// Leading-edge style: runs work immediately; subsequent same-id scheduling is handled by Store.
    /// Duration is applied as a cooldown gate before accepting another run with the same id.
    public func throttle(for duration: Duration) -> Effect {
        switch operation {
        case .none, .cancel:
            return self
        case .run(let id, let work):
            return Effect(operation: .run(id: id, work: {
                let result = try await work()
                try await Task.sleep(for: duration)
                try Task.checkCancellation()
                return result
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
            return Effect<NewAction>(operation: .run(id: id, work: {
                try await work().map(transform)
            }))
        case .merge(let effects):
            return .merge(effects.map { $0.map(transform) })
        }
    }
}
