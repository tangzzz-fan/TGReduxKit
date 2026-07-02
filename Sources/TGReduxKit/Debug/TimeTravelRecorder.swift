import Foundation

/// A single entry in the time-travel timeline.
///
/// Each entry captures the action dispatched, the state before and after
/// the reducer ran, and a wall-clock timestamp.
public struct TimelineEntry<State: Sendable, Action: Sendable>: Sendable {
    /// 0-based index in the timeline.
    public let index: Int

    /// The action that was dispatched.
    public let action: Action

    /// The state snapshot before the reducer processed this action.
    public let stateBefore: State

    /// The state snapshot after the reducer processed this action.
    public let stateAfter: State

    /// The wall-clock time when this action was dispatched.
    public let timestamp: Date
}

// MARK: - Recorder

/// Records a time-travel timeline of dispatched actions and state snapshots.
///
/// Attach `timeTravelMiddleware(recorder:)` to your Store to populate the
/// recorder automatically. Once recorded you can inspect the timeline, jump
/// back to earlier state snapshots, or export the timeline as JSON.
@MainActor
public final class TimeTravelRecorder<State: Sendable, Action: Sendable>: @preconcurrency Sendable {
    /// All recorded timeline entries, in dispatch order.
    public private(set) var entries: [TimelineEntry<State, Action>] = []

    /// Whether the recorder is active. When `false`, actions are not recorded.
    public var isRecording: Bool = true

    /// The maximum number of entries to keep. When exceeded the oldest entry
    /// is dropped. `nil` means unbounded.
    public var maxEntries: Int?

    public init() {}

    // MARK: - Recording

    /// Append a new timeline entry.
    ///
    /// Called automatically by `timeTravelMiddleware`. You typically do not
    /// call this directly.
    public func record(
        action: Action,
        stateBefore: State,
        stateAfter: State
    ) {
        guard isRecording else { return }

        let entry = TimelineEntry(
            index: entries.count,
            action: action,
            stateBefore: stateBefore,
            stateAfter: stateAfter,
            timestamp: Date()
        )

        entries.append(entry)

        if let max = maxEntries, entries.count > max {
            entries.removeFirst(entries.count - max)
        }
    }

    // MARK: - Navigation

    /// Return the `stateAfter` snapshot at the given index.
    ///
    /// Use this to inspect what the state looked like after a particular
    /// action was processed.
    public func snapshot(at index: Int) -> State? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index].stateAfter
    }

    /// Jump to the state *before* the first recorded action (the initial state).
    public var initialState: State? {
        entries.first?.stateBefore
    }

    // MARK: - Inspection

    /// Find all entries whose action matches the given predicate.
    public func filter(where predicate: (Action) -> Bool) -> [TimelineEntry<State, Action>] {
        entries.filter { predicate($0.action) }
    }

    /// All recorded actions, in order.
    public var actions: [Action] {
        entries.map(\.action)
    }

    /// Clear the timeline.
    public func clear() {
        entries.removeAll()
    }
}

// MARK: - JSON Export

extension TimeTravelRecorder where State: Encodable, Action: Encodable {
    /// A lightweight JSON structure for export.
    private struct ExportEntry: Encodable {
        let index: Int
        let timestamp: String
        let action: String  // JSON-encoded Action string
        let stateBefore: State
        let stateAfter: State
    }

    /// Export the full timeline as pretty-printed JSON data.
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let actionEncoder = JSONEncoder()
        let export = entries.map { entry -> ExportEntry in
            let actionJSON = (try? actionEncoder.encode(entry.action))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "\(entry.action)"
            return ExportEntry(
                index: entry.index,
                timestamp: ISO8601DateFormatter().string(from: entry.timestamp),
                action: actionJSON,
                stateBefore: entry.stateBefore,
                stateAfter: entry.stateAfter
            )
        }

        return try encoder.encode(export)
    }
}

// MARK: - Time Travel Middleware

/// Creates a middleware that records state snapshots before and after each
/// action is dispatched.
///
/// Attach this middleware to your Store to populate a `TimeTravelRecorder`.
///
/// ```swift
/// let recorder = TimeTravelRecorder<AppState, AppAction>()
/// let store = Store(
///     initialState: AppState(),
///     reducer: appReducer,
///     middlewares: [timeTravelMiddleware(recorder: recorder)]
/// )
/// ```
///
/// - Important: The State must be `Equatable` so the middleware can capture
///   the "before" snapshot. The middleware copies state **before** calling
///   `next(action)`, so `stateBefore` is guaranteed to be the state prior to
///   the reducer running.
public func timeTravelMiddleware<State: Equatable & Sendable, Action: Sendable>(
    recorder: TimeTravelRecorder<State, Action>
) -> Middleware<State, Action> {
    { store, action, next in
        let stateBefore = store.state
        next(action)
        recorder.record(action: action, stateBefore: stateBefore, stateAfter: store.state)
    }
}
