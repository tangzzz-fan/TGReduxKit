import Foundation

/// All actions must be safely shareable across isolation domains.
public protocol Action: Sendable {}

/// All state must be value-semantic and safely shareable across boundaries.
public protocol State: Equatable, Sendable {}
