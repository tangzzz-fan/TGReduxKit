import Testing
import Foundation
@testable import TGReduxKit

struct ErrorHandlingTests {
    struct TestState: Equatable {
        var data: String = ""
        var errorMessage: String = ""
        var errorSource: String = ""
    }

    enum TestAction: Equatable {
        case dataLoaded(String)
        case loadFailed(String, source: String)
    }

    struct TestErrorAction: ErrorAction {
        let error: Error
        let source: String
    }

    let reducer: (inout TestState, TestAction) -> Void = { state, action in
        switch action {
        case .dataLoaded(let data):
            state.data = data
        case .loadFailed(let message, let source):
            state.errorMessage = message
            state.errorSource = source
        }
    }

    // MARK: - runTask(catching:)

    @MainActor
    @Test func testRunTaskCatchingDispatchesOnError() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(id: "failing-task", catching: { error in
            .loadFailed(error.localizedDescription, source: "testSource")
        }) {
            throw NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.state.errorMessage == "Something went wrong")
        #expect(store.state.errorSource == "testSource")
        #expect(store.state.data == "")
    }

    @MainActor
    @Test func testRunTaskCatchingDispatchesOnSuccess() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(id: "success-task", catching: { error in
            .loadFailed(error.localizedDescription, source: "none")
        }) {
            await store.dispatch(.dataLoaded("success"))
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.state.data == "success")
        #expect(store.state.errorMessage == "")
    }

    @MainActor
    @Test func testRunTaskCatchingSilentlyDropsWhenNil() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(id: "silent-task", catching: { _ in nil }) {
            throw NSError(domain: "test", code: 1)
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.state.errorMessage == "")
    }

    // MARK: - errorReportingMiddleware

    @MainActor
    @Test func testErrorReportingMiddlewareWithExtractClosure() async throws {
        actor ErrorCollector {
            private var errors: [(String, String)] = []
            func append(error: String, source: String) {
                errors.append((error, source))
            }
            var all: [(String, String)] { errors }
        }

        let collector = ErrorCollector()
        let middleware: Middleware<TestState, TestAction> = errorReportingMiddleware(
            extract: { action in
                if case .loadFailed(let message, let source) = action {
                    return (error: NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: message]), source: source)
                }
                return nil
            },
            reporter: { error, source in
                Task {
                    await collector.append(error: error.localizedDescription, source: source)
                }
            }
        )

        let store = Store(initialState: TestState(), reducer: reducer, middlewares: [middleware])

        // This action matches → reporter fires
        store.dispatch(.loadFailed("Network timeout", source: "apiGateway"))

        // This action doesn't match → reporter doesn't fire
        store.dispatch(.dataLoaded("hello"))

        try await Task.sleep(nanoseconds: 50_000_000)

        let all = await collector.all
        #expect(all.count == 1)
        #expect(all[0].0 == "Network timeout")
        #expect(all[0].1 == "apiGateway")
    }

    @MainActor
    @Test func testErrorReportingMiddlewareSkipsNonMatchingActions() async throws {
        actor HitTracker {
            var hit = false
            func set() { hit = true }
        }
        let tracker = HitTracker()
        let middleware: Middleware<TestState, TestAction> = errorReportingMiddleware(
            extract: { _ in nil },
            reporter: { _, _ in Task { await tracker.set() } }
        )

        let store = Store(initialState: TestState(), reducer: reducer, middlewares: [middleware])
        store.dispatch(.dataLoaded("hello"))
        store.dispatch(.dataLoaded("world"))

        try await Task.sleep(nanoseconds: 30_000_000)

        let wasHit = await tracker.hit
        #expect(!wasHit)
    }

    // MARK: - Cancellation does not trigger catching

    @MainActor
    @Test func testCancelledTaskDoesNotTriggerCatching() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(id: "will-cancel", catching: { error in
            .loadFailed(error.localizedDescription, source: "should-not-fire")
        }) {
            try await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            throw NSError(domain: "test", code: 1)
        }

        // Cancel immediately
        store.cancelTask(id: "will-cancel")

        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(store.state.errorMessage == "")
    }
}
