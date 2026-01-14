import Foundation

/// Defines how a route should be presented modally.
public enum PresentationStyle: Sendable, Hashable {
    case sheet
    case fullScreenCover
}

/// A generic state container for managing navigation.
///
/// This state holds the current navigation path stack and any active modal presentation.
public struct NavigationState<Route: TGRoute>: Equatable, Sendable {
    /// The stack of routes for the navigation controller.
    public var path: [Route]
    
    /// The currently presented route (sheet or full screen cover).
    public var presentedRoute: Route?
    
    /// The style of the presented route.
    public var presentationStyle: PresentationStyle?
    
    public init(
        path: [Route] = [],
        presentedRoute: Route? = nil,
        presentationStyle: PresentationStyle? = nil
    ) {
        self.path = path
        self.presentedRoute = presentedRoute
        self.presentationStyle = presentationStyle
    }
}
