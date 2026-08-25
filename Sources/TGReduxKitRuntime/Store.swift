import Foundation
import Observation
import TGReduxKitCore

/// Main-actor observable state container. Owns effect scheduling and cancellation.
@MainActor
@Observable
public final class Store<State: Sendable, Action: Sendable> {
    public private(set) var state: State

    @ObservationIgnored
    private let reducer: Reducer<State, Action>

    @ObservationIgnored
    private var managedTasks: [CancellationID: Task<Void, Never>] = [:]

    public init(
        initialState: State,
        reducer: Reducer<State, Action>
    ) {
        self.state = initialState
        self.reducer = reducer
    }

    /// Fire-and-forget friendly. Returns a `Task` handle so callers may cancel; discard freely.
    @discardableResult
    public func dispatch(_ action: Action) -> Task<Void, Never>? {
        let effect = reducer.reduce(&state, action)
        return run(effect)
    }

    /// Awaits completion of the scheduled effect tree for this dispatch (not nested follow-ups' full trees beyond returned tasks).
    public func dispatchAndWait(_ action: Action) async {
        if let task = dispatch(action) {
            await task.value
        }
    }

    private func run(_ effect: Effect<Action>) -> Task<Void, Never>? {
        switch effect.operation {
        case .none:
            return nil

        case .cancel(let id):
            managedTasks[id]?.cancel()
            managedTasks[id] = nil
            return nil

        case .merge(let effects):
            let children = effects.compactMap { run($0) }
            guard !children.isEmpty else { return nil }
            return Task {
                for child in children {
                    await child.value
                }
            }

        case .run(let id, let work):
            let previous: Task<Void, Never>?
            if let id {
                previous = managedTasks[id]
                previous?.cancel()
            } else {
                previous = nil
            }

            let task = Task { [weak self] in
                if let previous {
                    await previous.value
                }
                guard !Task.isCancelled else { return }
                guard let self else { return }

                let send = Send<Action> { action in
                    await self.perform(action)
                }

                do {
                    try await work(send)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }

            if let id {
                managedTasks[id] = task
                Task { [weak self] in
                    await task.value
                    self?.finishTask(id: id, task: task)
                }
            }

            return task
        }
    }

    private func perform(_ action: Action) async {
        let effect = reducer.reduce(&state, action)
        if let task = run(effect) {
            await task.value
        }
    }

    private func finishTask(id: CancellationID, task: Task<Void, Never>) {
        if managedTasks[id] == task {
            managedTasks[id] = nil
        }
    }
}
