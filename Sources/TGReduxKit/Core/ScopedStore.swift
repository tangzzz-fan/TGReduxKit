import Foundation
import Observation

@MainActor
@Observable
public final class ScopedStore<State, Action>: StoreType, ScopeObserver {
    public private(set) var state: State

    @ObservationIgnored
    private let dispatchAction: ActionDispatcher<Action>

    @ObservationIgnored
    private let stateProvider: () -> State

    @ObservationIgnored
    private var childObservers: [UUID: WeakScopeObserver] = [:]

    internal init(
        initialState: State,
        dispatch: @escaping ActionDispatcher<Action>,
        stateProvider: @escaping () -> State
    ) {
        self.state = initialState
        self.dispatchAction = dispatch
        self.stateProvider = stateProvider
    }

    public func dispatch(_ action: Action) {
        dispatchAction(action)
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

    internal func addChildObserver(_ observer: any ScopeObserver) -> UUID {
        let id = UUID()
        childObservers[id] = WeakScopeObserver(observer)
        return id
    }

    func refreshStateFromParent() {
        let nextState = stateProvider()

        guard tgReduxKitStateChanged(from: state, to: nextState) else {
            return
        }

        state = nextState
        notifyChildObservers()
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
}
