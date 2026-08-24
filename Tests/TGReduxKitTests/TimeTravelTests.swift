import Testing
import Foundation
@testable import TGReduxKit

struct TimeTravelTests {
    struct TestState: Equatable, Sendable {
        var count: Int = 0
        var message: String = ""
    }

    enum TestAction: Equatable, Sendable {
        case increment
        case decrement
        case setMessage(String)
    }

    let reducer: Reducer<TestState, TestAction> = { state, action in
        switch action {
        case .increment:
            state.count += 1
        case .decrement:
            state.count -= 1
        case .setMessage(let msg):
            state.message = msg
        }
    }

    // MARK: - Recording

    @MainActor
    @Test func testRecorderCapturesBeforeAndAfterState() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)
        store.dispatch(.increment)
        store.dispatch(.setMessage("done"))

        #expect(recorder.entries.count == 3)

        // First entry: before = (0, ""), after = (1, "")
        #expect(recorder.entries[0].stateBefore.count == 0)
        #expect(recorder.entries[0].stateAfter.count == 1)

        // Second entry: before = (1, ""), after = (2, "")
        #expect(recorder.entries[1].stateBefore.count == 1)
        #expect(recorder.entries[1].stateAfter.count == 2)

        // Third entry: before = (2, ""), after = (2, "done")
        #expect(recorder.entries[2].stateBefore.message == "")
        #expect(recorder.entries[2].stateAfter.message == "done")
    }

    @MainActor
    @Test func testRecorderCapturesInitialState() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        let store = Store(
            initialState: TestState(count: 5),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)

        #expect(recorder.entries.first?.stateBefore.count == 5)
        #expect(recorder.initialState?.count == 5)
    }

    // MARK: - Navigation

    @MainActor
    @Test func testSnapshotAtIndex() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)
        store.dispatch(.increment)
        store.dispatch(.decrement)

        let afterFirst = recorder.snapshot(at: 0)
        #expect(afterFirst?.count == 1)

        let afterSecond = recorder.snapshot(at: 1)
        #expect(afterSecond?.count == 2)

        let afterThird = recorder.snapshot(at: 2)
        #expect(afterThird?.count == 1)

        // Out of bounds
        #expect(recorder.snapshot(at: 99) == nil)
    }

    // MARK: - Filtering

    @MainActor
    @Test func testFilterByAction() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)
        store.dispatch(.setMessage("a"))
        store.dispatch(.increment)
        store.dispatch(.setMessage("b"))

        let increments = recorder.filter { action in
            if case .increment = action { return true }
            return false
        }
        #expect(increments.count == 2)

        let messages = recorder.filter { action in
            if case .setMessage = action { return true }
            return false
        }
        #expect(messages.count == 2)

        // Verify the actions property
        let allActions = recorder.actions
        #expect(allActions.count == 4)
    }

    // MARK: - isRecording

    @MainActor
    @Test func testPauseRecording() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)
        #expect(recorder.entries.count == 1)

        recorder.isRecording = false
        store.dispatch(.increment)
        store.dispatch(.increment)
        #expect(recorder.entries.count == 1)  // Not recording

        recorder.isRecording = true
        store.dispatch(.decrement)
        #expect(recorder.entries.count == 2)  // Recording again
    }

    // MARK: - maxEntries

    @MainActor
    @Test func testMaxEntriesTrimsOldest() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        recorder.maxEntries = 2
        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)         // entry 0
        store.dispatch(.setMessage("a"))   // entry 1
        store.dispatch(.decrement)         // entry 2 (pushes entry 0 out)

        #expect(recorder.entries.count == 2)
        #expect(recorder.entries.first?.action == .setMessage("a"))
        #expect(recorder.entries.last?.action == .decrement)
        #expect(recorder.entries.map(\.index) == [1, 2])
        #expect(recorder.snapshot(at: 0)?.count == nil)
        #expect(recorder.snapshot(at: 1)?.message == "a")
        #expect(recorder.snapshot(at: 2)?.count == 0)
        #expect(recorder.initialState?.count == 0)
    }

    @MainActor
    @Test func testNegativeMaxEntriesClampsToZero() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)
        recorder.maxEntries = -1

        #expect(recorder.maxEntries == 0)
        #expect(recorder.entries.isEmpty)
        #expect(recorder.initialState?.count == 0)
    }

    // MARK: - Clear

    @MainActor
    @Test func testClear() {
        let recorder = TimeTravelRecorder<TestState, TestAction>()
        let store = Store(
            initialState: TestState(),
            reducer: reducer,
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.increment)
        store.dispatch(.increment)
        #expect(recorder.entries.count == 2)

        recorder.clear()
        #expect(recorder.entries.isEmpty)
        #expect(recorder.initialState == nil)
        #expect(recorder.snapshot(at: 0) == nil)
    }

    // MARK: - JSON export

    @MainActor
    @Test func testExportJSON() throws {
        struct CodableState: Equatable, Codable, Sendable {
            var value: Int = 0
        }

        enum CodableAction: Equatable, Codable, Sendable {
            case add(Int)
            case reset
        }

        let recorder = TimeTravelRecorder<CodableState, CodableAction>()
        let store = Store(
            initialState: CodableState(),
            reducer: { state, action in
                switch action {
                case .add(let n): state.value += n
                case .reset: state.value = 0
                }
            },
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.add(5))
        store.dispatch(.add(3))
        store.dispatch(.reset)

        let json = try recorder.exportJSON()
        #expect(json.count > 0)

        // Verify it's valid JSON
        let obj = try JSONSerialization.jsonObject(with: json) as? [Any]
        #expect(obj?.count == 3)
    }

    @MainActor
    @Test func testExportJSONThrowsWhenActionEncodingFails() {
        struct BrokenState: Equatable, Codable, Sendable {
            var value: Int = 0
        }

        struct BrokenAction: Equatable, Encodable, Sendable {
            func encode(to encoder: any Encoder) throws {
                struct ExportFailure: Error {}
                throw ExportFailure()
            }
        }

        let recorder = TimeTravelRecorder<BrokenState, BrokenAction>()
        let store = Store(
            initialState: BrokenState(),
            reducer: { _, _ in },
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(BrokenAction())

        do {
            _ = try recorder.exportJSON()
            Issue.record("Expected exportJSON() to propagate action encoding failures.")
        } catch {
            _ = Bool(true)
        }
    }

    // MARK: - Cross-feature recording

    @MainActor
    @Test func testCrossFeatureTimeline() {
        struct CartState: Equatable, Sendable {
            var items: [String] = []
            var total: Int = 0
        }

        enum ShoppingAction: Equatable, Sendable {
            case addItem(String, Int)
            case removeItem(String)
        }

        let recorder = TimeTravelRecorder<CartState, ShoppingAction>()
        let store = Store(
            initialState: CartState(),
            reducer: { state, action in
                switch action {
                case .addItem(let name, let price):
                    state.items.append(name)
                    state.total += price
                case .removeItem(let name):
                    state.items.removeAll { $0 == name }
                }
            },
            middlewares: [timeTravelMiddleware(recorder: recorder)]
        )

        store.dispatch(.addItem("Widget", 10))
        store.dispatch(.addItem("Gadget", 20))
        store.dispatch(.removeItem("Widget"))

        #expect(recorder.entries.count == 3)
        #expect(recorder.entries[0].stateAfter.total == 10)
        #expect(recorder.entries[1].stateAfter.total == 30)  // 10 + 20

        // Entry 2: remove Widget — total should reflect Widget's price was counted
        // (Our simple reducer only removes from items array; total is tracked
        //  by the reducer. This test verifies the recorder captures all states.)
        #expect(recorder.entries[2].stateAfter.items == ["Gadget"])
    }
}
