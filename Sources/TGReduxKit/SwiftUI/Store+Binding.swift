import SwiftUI

extension StoreType {
    /// Creates a Binding that reads a value from the state and dispatches an action when modified.
    ///
    /// Usage:
    /// ```swift
    /// TextField("Name", text: store.binding(get: \.name, send: { .updateName($0) }))
    /// ```
    ///
    /// - Parameters:
    ///   - get: A closure or KeyPath to retrieve the value from the state.
    ///   - send: A closure that creates an action from the new value.
    /// - Returns: A `Binding` to the value.
    public func binding<Value>(
        get: @escaping @Sendable (State) -> Value,
        send: @escaping @Sendable (Value) -> Action
    ) -> Binding<Value> {
        Binding(
            get: { get(self.state) },
            set: { newValue in self.dispatch(send(newValue)) }
        )
    }

    /// Creates a Binding using a KeyPath for the read side.
    public func binding<Value>(
        get keyPath: KeyPath<State, Value>,
        send: @escaping @Sendable (Value) -> Action
    ) -> Binding<Value> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { newValue in self.dispatch(send(newValue)) }
        )
    }
}
