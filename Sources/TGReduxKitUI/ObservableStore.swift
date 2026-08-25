import Foundation
import Observation
import SwiftUI
import TGReduxKitCore
import TGReduxKitRuntime

/// Alias kept for migration — Store is already `@MainActor @Observable`.
public typealias ObservableStore = Store

extension Store {
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
    public func provideStore<State: Sendable, Action: Sendable>(
        _ store: Store<State, Action>
    ) -> some View {
        environment(store)
    }
}
