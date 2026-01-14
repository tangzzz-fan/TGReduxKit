import Foundation

/// A type representing a navigation destination in the application.
///
/// Routes must be `Hashable` to work with SwiftUI's `NavigationStack`,
/// and `Sendable` to be safely used in Redux actions and state.
public protocol TGRoute: Hashable, Sendable, Identifiable {}

public extension TGRoute {
    /// Default implementation using the hash value as the identifier.
    var id: Int { hashValue }
}
