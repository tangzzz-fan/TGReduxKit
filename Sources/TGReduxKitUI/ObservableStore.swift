import Foundation
import Observation
import SwiftUI
import TGReduxKitCore
import TGReduxKitRuntime

/// Main-actor Observable projection over a Runtime `Store` actor.
@MainActor
@Observable
public final class ObservableStore<State: Sendable, Action: Sendable> {
    public private(set) var state: State

    @ObservationIgnored
    private let store: Store<State, Action>

    public init(
        initialState: State,
        reducer: Reducer<State, Action>,
        dependencies: DependencyContext = .live
    ) {
        self.state = initialState
        self.store = Store(
            initialState: initialState,
            reducer: reducer,
            dependencies: dependencies
        )

        let store = self.store
        Task { [weak self] in
            await store.setStateHandler { snapshot in
                await MainActor.run {
                    self?.state = snapshot
                }
            }
        }
    }

    public func dispatch(_ action: Action) {
        Task { await store.dispatch(action) }
    }

    public func dispatchAndWait(_ action: Action) async {
        _ = await store.dispatch(action)
    }

    public func binding<Value>(
        get: @escaping (State) -> Value,
        send: @escaping (Value) -> Action
    ) -> Binding<Value> {
        Binding(
            get: { get(self.state) },
            set: { self.dispatch(send($0)) }
        )
    }

    public func binding<Value>(
        get: KeyPath<State, Value>,
        send: @escaping (Value) -> Action
    ) -> Binding<Value> {
        binding(get: { $0[keyPath: get] }, send: send)
    }
}

extension View {
    /// Injects an `ObservableStore` for descendant views via environment object-style access.
    public func provideStore<State: Sendable, Action: Sendable>(
        _ store: ObservableStore<State, Action>
    ) -> some View {
        environment(store)
    }
}
