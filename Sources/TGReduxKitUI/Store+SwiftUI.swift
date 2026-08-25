import SwiftUI
import TGReduxKitCore
import TGReduxKitRuntime

public extension View {
    /// Injects a root `Store` for descendant views via the Observation environment.
    func provideStore<State: TGReduxKitCore.State, Action: TGReduxKitCore.Action>(
        _ store: Store<State, Action>
    ) -> some View {
        environment(store)
    }
}

public extension StoreType {
    func binding<Value>(
        get: @escaping (State) -> Value,
        send: @escaping (Value) -> Action
    ) -> Binding<Value> {
        Binding(
            get: { get(self.state) },
            set: { self.dispatch(send($0)) }
        )
    }

    func binding<Value>(
        get keyPath: KeyPath<State, Value>,
        send: @escaping (Value) -> Action
    ) -> Binding<Value> {
        binding(get: { $0[keyPath: keyPath] }, send: send)
    }
}
