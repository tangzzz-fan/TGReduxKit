import Foundation

/// Injectable dependencies available to every reduce invocation.
public struct DependencyContext: Sendable {
    public var uuid: @Sendable () -> UUID
    public var date: @Sendable () -> Date
    public var sleep: @Sendable (Duration) async throws -> Void

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
    }

    public static let live = DependencyContext()

    public static let immediate = DependencyContext(
        sleep: { _ in }
    )
}
