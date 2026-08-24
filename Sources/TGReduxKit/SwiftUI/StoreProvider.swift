import SwiftUI
import Observation

extension View {
    /// Injects a store-like type into the SwiftUI environment.
    ///
    /// Use this modifier at the root of your view hierarchy to make a `Store`
    /// or `ScopedStore` available to all child views via `@Environment`.
    ///
    /// - Parameter store: The store instance to inject.
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
    public func provideStore<S: StoreType>(_ store: S) -> some View {
        self.environment(store)
    }
}
