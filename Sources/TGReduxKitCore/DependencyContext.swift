import Foundation

/// Declares a typed dependency available through `DependencyContext`.
public protocol DependencyKey: Sendable {
    associatedtype Value: Sendable
    static var liveValue: Value { get }
}

/// Injectable dependencies available to every reduce invocation.
public struct DependencyContext: Sendable {
    public var uuid: @Sendable () -> UUID
    public var date: @Sendable () -> Date
    public var sleep: @Sendable (Duration) async throws -> Void

    private var values: [ObjectIdentifier: any Sendable]

    public init(
        uuid: @escaping @Sendable () -> UUID = { UUID() },
        date: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.uuid = uuid
        self.date = date
        self.sleep = sleep
        self.values = [:]
    }

    public static let live = DependencyContext()

    public static let immediate = DependencyContext(
        sleep: { _ in }
    )

    /// Typed app/framework dependencies. Unset keys resolve to `Key.liveValue`.
    public subscript<Key: DependencyKey>(_ key: Key.Type) -> Key.Value {
        get {
            if let value = values[ObjectIdentifier(key)] as? Key.Value {
                return value
            }
            return Key.liveValue
        }
        set {
            values[ObjectIdentifier(key)] = newValue
        }
    }
}
