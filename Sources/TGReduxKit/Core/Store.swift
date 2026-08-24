import Foundation
import Observation

extension Equatable {
    fileprivate func tgReduxKitEquals(_ other: Any) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

@MainActor
func tgReduxKitStateChanged<State>(from oldValue: State, to newValue: State) -> Bool {
    guard let equatableValue = oldValue as? any Equatable else {
        return true
    }

    return !equatableValue.tgReduxKitEquals(newValue)
}

@MainActor
@Observable
public final class Store<State, Action>: StoreType {
    public private(set) var state: State

    @ObservationIgnored
    private let reducer: Reducer<State, Action>

    @ObservationIgnored
    private let middlewares: [Middleware<State, Action>]

    @ObservationIgnored
    private var dispatchFunction: ActionDispatcher<Action>!

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

        let initialDispatch: ActionDispatcher<Action> = { [weak self] action in
            guard let self else { return }

            self.applyReducer(action)
        }

        self.dispatchFunction = middlewares.reversed().reduce(initialDispatch) { nextDispatch, middleware in
            { [weak self] action in
                guard let self else { return }

                middleware(self, action, nextDispatch)
            }
        }
    }

    public func dispatch(_ action: Action) {
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
            stateProvider: {
                return self.state[keyPath: keyPath]
            }
        )

        _ = addChildObserver(childStore)

        return childStore
    }

    @discardableResult
    public func runTask(
        id: CancellationID? = nil,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let previousTask = id.flatMap { managedTasks[$0]?.task }
        if let id {
            cancelTask(id: id)
        }

        let token = UUID()
        let task = Task(priority: priority) { [weak self] in
            if let previousTask {
                await previousTask.value
            }

            guard !Task.isCancelled else {
                guard let self, let id else { return }
                self.finishTask(id: id, token: token)
                return
            }
            await operation()

            guard let self, let id else { return }
            self.finishTask(id: id, token: token)
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

    internal func hasManagedTask(id: CancellationID) -> Bool {
        managedTasks[id] != nil
    }

    internal func addChildObserver(_ observer: any ScopeObserver) -> UUID {
        let id = UUID()
        childObservers[id] = WeakScopeObserver(observer)
        return id
    }

    private func notifyChildObservers() {
        let observerSnapshot = childObservers
        for entry in observerSnapshot {
            guard let observer = entry.value.value else {
                childObservers.removeValue(forKey: entry.key)
                continue
            }

            observer.refreshStateFromParent()
        }
    }

    private func finishTask(id: CancellationID, token: UUID) {
        guard let task = managedTasks[id], task.token == token else { return }
        managedTasks.removeValue(forKey: id)
    }

    fileprivate func applyReducer(_ action: Action) {
        let currentState = state
        guard currentState is any Equatable else {
            reducer(&state, action)
            notifyChildObservers()
            return
        }

        var nextState = currentState
        reducer(&nextState, action)

        guard tgReduxKitStateChanged(from: currentState, to: nextState) else {
            return
        }

        state = nextState
        notifyChildObservers()
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
