import Foundation

/// Declarative side-effect description.
/// An `Effect` does not execute work itself — `Store` interprets and runs it.
public struct Effect<Action: Sendable>: Sendable {
    public enum Operation: Sendable {
        case none
        case task(
            id: CancellationID?,
            priority: TaskPriority?,
            operation: @Sendable () async -> Action?
        )
        case cancel(CancellationID)
        indirect case merge([Effect<Action>])
    }

    public let operation: Operation

    private init(operation: Operation) {
        self.operation = operation
    }

    public static func none() -> Self {
        Self(operation: .none)
    }

    public static func task(
        id: CancellationID? = nil,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Action?
    ) -> Self {
        Self(operation: .task(id: id, priority: priority, operation: operation))
    }

    public static func cancel(id: CancellationID) -> Self {
        Self(operation: .cancel(id))
    }

    public static func merge(_ effects: Effect<Action>...) -> Self {
        merge(Array(effects))
    }

    public static func merge(_ effects: [Effect<Action>]) -> Self {
        let flattened = effects.filter {
            if case .none = $0.operation { return false }
            return true
        }
        if flattened.isEmpty { return .none() }
        if flattened.count == 1 { return flattened[0] }
        return Self(operation: .merge(flattened))
    }

    public static func fireAndForget(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Self {
        .task(id: nil, priority: priority, operation: {
            await operation()
            return nil
        })
    }

    public static func debounce(
        id: CancellationID,
        delay: Duration,
        operation: @escaping @Sendable () async -> Action?
    ) -> Self {
        .task(id: id) {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return nil }
            return await operation()
        }
    }

    public func map<NewAction: Sendable>(
        _ transform: @escaping @Sendable (Action) -> NewAction
    ) -> Effect<NewAction> {
        switch operation {
        case .none:
            return .none()
        case .cancel(let id):
            return .cancel(id: id)
        case .task(let id, let priority, let work):
            return .task(id: id, priority: priority) {
                await work().map(transform)
            }
        case .merge(let effects):
            return .merge(effects.map { $0.map(transform) })
        }
    }
}
