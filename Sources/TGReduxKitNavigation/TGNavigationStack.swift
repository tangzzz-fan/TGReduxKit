import SwiftUI
import TGReduxKit

/// A wrapper around `NavigationStack` that connects to `NavigationState` and
/// dispatches `NavigationAction`s back into your reducer pipeline.
///
/// This target is intentionally separate from the core store module so apps can
/// adopt TGReduxKit's state model without pulling in the SwiftUI navigation
/// adapter unless they want it.
public struct TGNavigationStack<Route: TGRoute, Root: View, Destination: View>: View {
    private let state: NavigationState<Route>
    private let dispatch: @MainActor (NavigationAction<Route>) -> Void
    private let root: () -> Root
    private let destination: (Route) -> Destination

    public init(
        state: NavigationState<Route>,
        dispatch: @escaping @MainActor (NavigationAction<Route>) -> Void,
        @ViewBuilder root: @escaping () -> Root,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self.state = state
        self.dispatch = dispatch
        self.root = root
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(
            path: Binding(
                get: { state.path },
                set: { dispatch(.setPath($0)) }
            )
        ) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .sheet(
            item: Binding(
                get: { state.presentationStyle == .sheet ? state.presentedRoute : nil },
                set: {
                    if $0 == nil {
                        dispatch(.dismiss)
                    }
                }
            )
        ) { route in
            destination(route)
        }
        #if os(iOS) || os(tvOS)
        .fullScreenCover(
            item: Binding(
                get: { state.presentationStyle == .fullScreenCover ? state.presentedRoute : nil },
                set: {
                    if $0 == nil {
                        dispatch(.dismiss)
                    }
                }
            )
        ) { route in
            destination(route)
        }
        #endif
    }
}
