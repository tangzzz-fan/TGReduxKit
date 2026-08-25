import Foundation
import Observation
import TGReduxKitCore

@MainActor
@Observable
public final class Store<State: TGReduxKitCore.State, Action: TGReduxKitCore.Action>: StoreType {
    public private(set) var state: State

    @ObservationIgnored
    private let reducer: Reducer<State, Action>

    @ObservationIgnored
    private let middlewares: [Middleware<State, Action>]

    @ObservationIgnored
    private var dispatchFunction: @MainActor (Action) -> Effect<Action> = { _ in .none() }

    @ObservationIgnored
    private var managedTasks: [CancellationID: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var childObservers: [UUID: WeakScopeObserver] = [:]

    public init(
        initialState: State,
        reducer: @escaping Reducer<State, Action>,
        middlewares: [Middleware<State, Action>] = []
    ) {
        self.state = initialState
        self.reducer = reducer
        self.middlewares = middlewares
        rebuildDispatchChain()
    }

    public func dispatch(_ action: Action) {
        let effect = dispatchFunction(action)
        execute(effect)
    }

    // MARK: - Scoping

    public func scope<ChildState: TGReduxKitCore.State, ChildAction: TGReduxKitCore.Action>(
        state keyPath: KeyPath<State, ChildState>,
        action actionTransform: @escaping (ChildAction) -> Action
    ) -> ScopedStore<ChildState, ChildAction> {
        let child = ScopedStore<ChildState, ChildAction>(
            stateProvider: { [weak self] in
                guard let self else {
                    fatalError("Store deallocated during state read")
                }
                return self.state[keyPath: keyPath]
            },
            dispatch: { [weak self] childAction in
                self?.dispatch(actionTransform(childAction))
            }
        )
        _ = addChildObserver(child)
        return child
    }

    // MARK: - Task lifecycle (root-only)

    @discardableResult
    public func runTask(
        id: CancellationID? = nil,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Action?
    ) -> Task<Void, Never> {
        if let id {
            cancelTask(id: id)
        }

        let task = Task(priority: priority) { [weak self] in
            guard !Task.isCancelled else { return }

            let action = await operation()

            guard let self, let action, !Task.isCancelled else { return }
            self.dispatch(action)

            if let id {
                self.managedTasks.removeValue(forKey: id)
            }
        }

        if let id {
            managedTasks[id] = task
        }

        return task
    }

    @discardableResult
    public func runTask(
        id: CancellationID? = nil,
        catching: @escaping @Sendable (Error) -> Action?,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Task<Void, Never> {
        runTask(id: id, priority: priority) {
            do {
                try await operation()
                return nil
            } catch {
                guard !Task.isCancelled else { return nil }
                return catching(error)
            }
        }
    }

    public func cancelTask(id: CancellationID) {
        managedTasks.removeValue(forKey: id)?.cancel()
    }

    public func cancelAllTasks() {
        let tasks = Array(managedTasks.values)
        managedTasks.removeAll()
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Private

    private func rebuildDispatchChain() {
        let final: @MainActor (Action) -> Effect<Action> = { [weak self] action in
            self?.applyReducer(action)
            return .none()
        }

        dispatchFunction = middlewares.reversed().reduce(final) { next, middleware in
            { [weak self] action in
                guard let self else { return .none() }
                return middleware(self, action, next)
            }
        }
    }

    private func applyReducer(_ action: Action) {
        let oldState = state
        reducer(&state, action)
        if state != oldState {
            notifyChildObservers()
        }
    }

    private func execute(_ effect: Effect<Action>) {
        switch effect.operation {
        case .none:
            break
        case .task(let id, let priority, let work):
            _ = runTask(id: id, priority: priority, operation: work)
        case .cancel(let id):
            cancelTask(id: id)
        case .merge(let effects):
            effects.forEach { execute($0) }
        }
    }

    func addChildObserver(_ observer: any ScopeObserver) -> UUID {
        let id = UUID()
        childObservers[id] = WeakScopeObserver(observer)
        return id
    }

    private func notifyChildObservers() {
        let snapshot = childObservers
        for entry in snapshot {
            guard let observer = entry.value.value else {
                childObservers.removeValue(forKey: entry.key)
                continue
            }
            observer.refreshStateFromParent()
        }
    }
}

// MARK: - Scope observation

@MainActor
protocol ScopeObserver: AnyObject {
    func refreshStateFromParent()
}

@MainActor
struct WeakScopeObserver {
    weak var value: (any ScopeObserver)?

    init(_ value: (any ScopeObserver)?) {
        self.value = value
    }
}
