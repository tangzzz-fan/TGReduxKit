import Foundation
import Observation
import TGReduxKitCore

/// Pure projection — no task registry. Async work flows back to the root `Store` via `dispatch`.
@MainActor
@Observable
public final class ScopedStore<State: TGReduxKitCore.State, Action: TGReduxKitCore.Action>: StoreType, ScopeObserver {
    public private(set) var state: State

    @ObservationIgnored
    private let dispatchAction: (Action) -> Void

    @ObservationIgnored
    private let stateProvider: () -> State

    @ObservationIgnored
    private var childObservers: [UUID: WeakScopeObserver] = [:]

    init(
        stateProvider: @escaping () -> State,
        dispatch: @escaping (Action) -> Void
    ) {
        self.stateProvider = stateProvider
        self.dispatchAction = dispatch
        self.state = stateProvider()
    }

    public func dispatch(_ action: Action) {
        dispatchAction(action)
    }

    public func scope<ChildState: TGReduxKitCore.State, ChildAction: TGReduxKitCore.Action>(
        state keyPath: KeyPath<State, ChildState>,
        action actionTransform: @escaping (ChildAction) -> Action
    ) -> ScopedStore<ChildState, ChildAction> {
        let child = ScopedStore<ChildState, ChildAction>(
            stateProvider: { [weak self] in
                guard let self else {
                    fatalError("ScopedStore deallocated during state read")
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

    func refreshStateFromParent() {
        let nextState = stateProvider()
        guard nextState != state else { return }
        state = nextState
        notifyChildObservers()
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

    func addChildObserver(_ observer: any ScopeObserver) -> UUID {
        let id = UUID()
        childObservers[id] = WeakScopeObserver(observer)
        return id
    }
}
