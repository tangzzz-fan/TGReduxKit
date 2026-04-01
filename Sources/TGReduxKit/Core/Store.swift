import Foundation
import Observation

@MainActor
@Observable
public final class Store<State, Action> {
    public private(set) var state: State

    @ObservationIgnored
    private let reducer: Reducer<State, Action>

    @ObservationIgnored
    private let middlewares: [Middleware<State, Action>]

    @ObservationIgnored
    private var childObservers: [UUID: WeakScopeObserver] = [:]

    @ObservationIgnored
    private var managedTasks: [CancellationID: ManagedTask] = [:]

    public init(
        initialState: State,
        reducer: @escaping Reducer<State, Action>,
        middlewares: [Middleware<State, Action>] = []
    ) {
        self.state = initialState
        self.reducer = reducer
        self.middlewares = middlewares
    }

    public func dispatch(_ action: Action) {
        let initialDispatch: Dispatch<Action> = { [weak self] action in
            guard let self else { return }

            self.reducer(&self.state, action)
            self.notifyChildObservers()
        }

        let dispatchFunction = middlewares.reversed().reduce(initialDispatch) { nextDispatch, middleware in
            { [weak self] action in
                guard let self else { return }

                middleware(self, action, nextDispatch)
            }
        }

        dispatchFunction(action)
    }

    public func scope<ChildState, ChildAction>(
        state keyPath: KeyPath<State, ChildState>,
        action actionTransform: @escaping (ChildAction) -> Action
    ) -> ScopedStore<ChildState, ChildAction> {
        let childStore = ScopedStore<ChildState, ChildAction>(
            initialState: state[keyPath: keyPath],
            dispatch: { [weak self] childAction in
                self?.dispatch(actionTransform(childAction))
            },
            stateProvider: { [weak self] in
                guard let self else {
                    fatalError("Store scope accessed after deallocation")
                }

                return self.state[keyPath: keyPath]
            }
        )

        addChildObserver(childStore)

        return childStore
    }

    @discardableResult
    public func runTask(
        id: CancellationID? = nil,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        if let id {
            cancelTask(id: id)
        }

        let token = UUID()
        let task = Task(priority: priority) { [weak self] in
            await operation()

            guard let self, let id else { return }
            await self.finishTask(id: id, token: token)
        }

        if let id {
            managedTasks[id] = ManagedTask(token: token, task: task)
        }

        return task
    }

    public func cancelTask(id: CancellationID) {
        guard let task = managedTasks.removeValue(forKey: id) else { return }
        task.task.cancel()
    }

    public func cancelAllTasks() {
        let tasks = managedTasks.values.map(\.task)
        managedTasks.removeAll()
        tasks.forEach { $0.cancel() }
    }

    internal func addChildObserver(_ observer: any ScopeObserver) -> UUID {
        let id = UUID()
        childObservers[id] = WeakScopeObserver(observer)
        return id
    }

    private func notifyChildObservers() {
        childObservers = childObservers.reduce(into: [:]) { partialResult, entry in
            guard let observer = entry.value.value else { return }
            partialResult[entry.key] = WeakScopeObserver(observer)
            observer.refreshStateFromParent()
        }
    }

    private func finishTask(id: CancellationID, token: UUID) {
        guard let task = managedTasks[id], task.token == token else { return }
        managedTasks.removeValue(forKey: id)
    }
}

private struct ManagedTask {
    let token: UUID
    let task: Task<Void, Never>
}

@MainActor
protocol ScopeObserver: AnyObject {
    func refreshStateFromParent()
}

struct WeakScopeObserver {
    weak var value: (any ScopeObserver)?

    init(_ value: any ScopeObserver) {
        self.value = value
    }
}
