import Foundation
import Observation

@MainActor
@Observable
public final class ScopedStore<State, Action>: ScopeObserver {
    public private(set) var state: State

    @ObservationIgnored
    private let dispatchAction: Dispatch<Action>

    @ObservationIgnored
    private let stateProvider: () -> State

    @ObservationIgnored
    private var childObservers: [UUID: WeakScopeObserver] = [:]

    internal init(
        initialState: State,
        dispatch: @escaping Dispatch<Action>,
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
            stateProvider: { [weak self] in
                guard let self else {
                    fatalError("ScopedStore state accessed after deallocation")
                }

                return self.state[keyPath: keyPath]
            }
        )

        addChildObserver(childStore)

        return childStore
    }

    internal func addChildObserver(_ observer: any ScopeObserver) -> UUID {
        let id = UUID()
        childObservers[id] = WeakScopeObserver(observer)
        return id
    }

    func refreshStateFromParent() {
        state = stateProvider()
        notifyChildObservers()
    }

    private func notifyChildObservers() {
        childObservers = childObservers.reduce(into: [:]) { partialResult, entry in
            guard let observer = entry.value.value else { return }
            partialResult[entry.key] = WeakScopeObserver(observer)
            observer.refreshStateFromParent()
        }
    }
}
