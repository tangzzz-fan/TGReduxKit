import SwiftUI

/// A debug inspector that visualises the recorded action timeline from a
/// ``TimeTravelRecorder``.
///
/// Embed this view in a debug menu or present it as a sheet during development.
///
/// ## Example
///
/// ```swift
/// @main
/// struct MyApp: App {
///     let recorder = TimeTravelRecorder<AppState, AppAction>()
///
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .toolbar {
///                     ToolbarItem(placement: .navigationBarTrailing) {
///                         NavigationLink("Timeline") {
///                             TimelineInspector(recorder: recorder)
///                         }
///                     }
///                 }
///         }
///     }
/// }
/// ```
public struct TimelineInspector<State: Sendable, Action: Sendable>: View {
    /// The recorder whose timeline to display.
    let recorder: TimeTravelRecorder<State, Action>

    /// A human-readable label for each action.
    let actionLabel: (Action) -> String

    /// An optional human-readable summary of a state snapshot.
    let stateSummary: (State) -> String

    /// Creates a new timeline inspector.
    ///
    /// - Parameters:
    ///   - recorder: The recorder to inspect.
    ///   - actionLabel: A closure that returns a short label for an action.
    ///   - stateSummary: A closure that returns a short summary of the state.
    public init(
        recorder: TimeTravelRecorder<State, Action>,
        actionLabel: @escaping (Action) -> String = { "\($0)" },
        stateSummary: @escaping (State) -> String = { "\($0)" }
    ) {
        self.recorder = recorder
        self.actionLabel = actionLabel
        self.stateSummary = stateSummary
    }

    public var body: some View {
        List {
            Section {
                HStack {
                    Text("Total actions")
                    Spacer()
                    Text("\(recorder.entries.count)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Recording")
                    Spacer()
                    Text(recorder.isRecording ? "On" : "Paused")
                        .foregroundStyle(recorder.isRecording ? .green : .orange)
                }
            } header: {
                Text("Overview")
            }

            Section("Actions") {
                if recorder.entries.isEmpty {
                    Text("Dispatch an action to see it here.")
                        .foregroundStyle(.secondary)
                        .italic()
                }

                ForEach(recorder.entries, id: \.index) { entry in
                    NavigationLink {
                        TimelineEntryDetail(
                            entry: entry,
                            actionLabel: actionLabel,
                            stateSummary: stateSummary
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(actionLabel(entry.action))
                                .font(.body)
                            Text("#\(entry.index) · \(entry.timestamp.formatted(date: .omitted, time: .standard))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack {
                    Button("Clear") { recorder.clear() }
                        .disabled(recorder.entries.isEmpty)

                    Spacer()

                    Button(recorder.isRecording ? "Pause" : "Resume") {
                        recorder.isRecording.toggle()
                    }
                }
            }
        }
    }
}

// MARK: - Entry Detail

private struct TimelineEntryDetail<State: Sendable, Action: Sendable>: View {
    let entry: TimelineEntry<State, Action>
    let actionLabel: (Action) -> String
    let stateSummary: (State) -> String

    var body: some View {
        List {
            Section("Action") {
                Text(actionLabel(entry.action))
                    .font(.title3.monospaced())
            }

            Section("State Before") {
                Text(stateSummary(entry.stateBefore))
                    .font(.callout.monospaced())
            }

            Section("State After") {
                Text(stateSummary(entry.stateAfter))
                    .font(.callout.monospaced())
            }

            Section("Metadata") {
                LabeledContent("Index", value: "#\(entry.index)")
                LabeledContent("Timestamp", value: entry.timestamp.formatted(date: .numeric, time: .standard))
            }
        }
        .navigationTitle("Entry #\(entry.index)")
    }
}
