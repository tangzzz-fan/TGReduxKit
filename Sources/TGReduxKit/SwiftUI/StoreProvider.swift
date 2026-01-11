import SwiftUI

extension View {
    /// Injects a Store into the SwiftUI environment.
    ///
    /// Use this modifier at the root of your view hierarchy to make the Store available
    /// to all child views via `@Environment`.
    ///
    /// - Parameter store: The `Store` instance to inject.
    /// - Returns: A view with the store in its environment.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     let store = Store(...)
    ///
    ///     var body: some Scene {
    ///         WindowGroup {
    ///             ContentView()
    ///                 .provideStore(store)
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Inside a child view:
    ///
    /// ```swift
    /// struct ContentView: View {
    ///     @Environment(Store<AppState, AppAction>.self) var store
    /// }
    /// ```
    public func provideStore<State, Action>(_ store: Store<State, Action>) -> some View {
        self.environment(store)
    }
}
