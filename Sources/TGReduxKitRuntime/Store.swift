import Foundation
import TGReduxKitCore

/// Actor-isolated state container. Owns mutation and Effect scheduling.
public actor Store<State: Sendable, Action: Sendable> {
    public private(set) var state: State

    private let reducer: Reducer<State, Action>
    private var dependencies: DependencyContext
    private var managedTasks: [CancellationID: Task<Void, Never>] = [:]
    private var stateHandler: (@Sendable (State) async -> Void)?

    public init(
        initialState: State,
        reducer: Reducer<State, Action>,
        dependencies: DependencyContext = .live
    ) {
        self.state = initialState
        self.reducer = reducer
        self.dependencies = dependencies
    }

    /// Registers an async observer invoked after each successful reduce (before/with effects).
    public func setStateHandler(_ handler: (@Sendable (State) async -> Void)?) {
        self.stateHandler = handler
    }

    public func withDependencies(
        _ update: @Sendable (inout DependencyContext) -> Void
    ) {
        update(&dependencies)
    }

    /// Synchronously reduces `action`, notifies observers, then runs the returned effect.
    @discardableResult
    public func dispatch(_ action: Action) async -> State {
        let effect = reducer.reduce(&state, action, dependencies)
        let snapshot = state
        if let stateHandler {
            await stateHandler(snapshot)
        }
        await run(effect)
        return snapshot
    }

    public func currentState() -> State {
        state
    }

    private func run(_ effect: Effect<Action>) async {
        switch effect.operation {
        case .none:
            return

        case .cancel(let id):
            cancelTask(id: id)

        case .merge(let effects):
            await withTaskGroup(of: Void.self) { group in
                for child in effects {
                    group.addTask { await self.run(child) }
                }
            }

        case .run(let id, let work):
            if let id {
                cancelTask(id: id)
            }

            let previous = id.flatMap { managedTasks[$0] }
            let task = Task { [weak self] in
                if let previous {
                    await previous.value
                }
                guard !Task.isCancelled else { return }
                do {
                    guard let action = try await work() else { return }
                    guard !Task.isCancelled else { return }
                    await self?.dispatch(action)
                } catch is CancellationError {
                    return
                } catch {
                    // Swallow non-cancellation errors; domain should map failures into Action.
                    return
                }
            }

            if let id {
                managedTasks[id] = task
                Task { [weak self] in
                    await task.value
                    await self?.finishTask(id: id, task: task)
                }
            }
        }
    }

    private func cancelTask(id: CancellationID) {
        managedTasks[id]?.cancel()
        managedTasks[id] = nil
    }

    private func finishTask(id: CancellationID, task: Task<Void, Never>) {
        if managedTasks[id] == task {
            managedTasks[id] = nil
        }
    }
}
