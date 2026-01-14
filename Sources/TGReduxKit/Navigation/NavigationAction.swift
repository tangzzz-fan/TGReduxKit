import Foundation

/// Actions for manipulating the navigation state.
public enum NavigationAction<Route: TGRoute>: Equatable, Sendable {
    /// Pushes a new route onto the navigation stack.
    case push(Route)
    
    /// Pops the top route from the navigation stack.
    case pop
    
    /// Pops all routes, returning to the root.
    case popToRoot
    
    /// Presents a route modally.
    case present(Route, style: PresentationStyle = .sheet)
    
    /// Dismisses the currently presented route.
    case dismiss
}
