import SwiftUI

/// A wrapper around `NavigationStack` that connects to the Redux store.
///
/// This view manages the synchronization between the `NavigationState` in your Store
/// and the SwiftUI navigation system.
public struct TGNavigationStack<Route: TGRoute, Root: View, Destination: View>: View {
    
    @Binding private var state: NavigationState<Route>
    private let root: () -> Root
    private let destination: (Route) -> Destination
    
    /// Initializes the navigation stack with a binding to the navigation state.
    ///
    /// - Parameters:
    ///   - state: A binding to the `NavigationState` in your Redux store.
    ///   - root: The root view of the navigation stack.
    ///   - destination: A view builder that produces the destination view for a given route.
    public init(
        state: Binding<NavigationState<Route>>,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._state = state
        self.root = root
        self.destination = destination
    }
    
    public var body: some View {
        NavigationStack(path: $state.path) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .sheet(
            item: Binding(
                get: { state.presentationStyle == .sheet ? state.presentedRoute : nil },
                set: { if $0 == nil { 
                    state.presentedRoute = nil
                    state.presentationStyle = nil
                } }
            )
        ) { route in
            destination(route)
        }
        .fullScreenCover(
            item: Binding(
                get: { state.presentationStyle == .fullScreenCover ? state.presentedRoute : nil },
                set: { if $0 == nil { 
                    state.presentedRoute = nil
                    state.presentationStyle = nil
                } }
            )
        ) { route in
            destination(route)
        }
    }
}

