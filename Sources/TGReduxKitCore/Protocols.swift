import Foundation

/// Marker for Redux actions. All actions must be safely shareable across isolation domains.
public protocol ReduxAction: Sendable {}

/// Marker for Redux state. State values cross actor boundaries as snapshots.
public protocol ReduxState: Sendable {}
