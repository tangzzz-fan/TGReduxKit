import Testing
import Foundation
@testable import TGReduxKit

struct AsyncPrimitivesTests {
    struct TestState: Equatable {
        var count: Int = 0
        var message: String = ""
        var items: [String] = []
    }

    enum TestAction: Equatable, Sendable {
        case increment
        case setMessage(String)
        case appendItem(String)
        case timeoutFallback
    }

    let reducer: Reducer<TestState, TestAction> = { state, action in
        switch action {
        case .increment:
            state.count += 1
        case .setMessage(let msg):
            state.message = msg
        case .appendItem(let item):
            state.items.append(item)
        case .timeoutFallback:
            state.message = "timeout"
        }
    }

    // MARK: - Debounce

    @MainActor
    @Test func testDebounceCancelsPreviousTask() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        // First debounce will be cancelled by the second
        store.debounce(id: "debounce-test", milliseconds: 50) {
            await store.dispatch(.appendItem("first"))
        }

        // Second debounce cancels first and executes
        store.debounce(id: "debounce-test", milliseconds: 50) {
            await store.dispatch(.appendItem("second"))
        }

        // Wait long enough for the second to complete
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(store.state.items == ["second"])
    }

    @MainActor
    @Test func testDebounceDelaysExecution() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.debounce(id: "delay-test", milliseconds: 100) {
            await store.dispatch(.setMessage("delayed"))
        }

        // Should not have executed yet
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(store.state.message == "")

        // Should have executed by now
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(store.state.message == "delayed")
    }

    // MARK: - Throttle

    @MainActor
    @Test func testThrottleExecutesImmediately() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.throttle(id: "throttle-test", milliseconds: 200) {
            await store.dispatch(.increment)
        }

        // Immediate execution
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(store.state.count == 1)
    }

    @MainActor
    @Test func testThrottleIgnoresCallsWithinWindow() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.throttle(id: "throttle-window", milliseconds: 200) {
            await store.dispatch(.appendItem("first"))
        }

        store.throttle(id: "throttle-window", milliseconds: 200) {
            await store.dispatch(.appendItem("second"))
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.state.items == ["first"])

        try await Task.sleep(nanoseconds: 220_000_000)

        store.throttle(id: "throttle-window", milliseconds: 200) {
            await store.dispatch(.appendItem("third"))
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.state.items == ["first", "third"])
    }

    @MainActor
    @Test func testThrottleHoldsLockUntilInFlightOperationFinishes() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.throttle(id: "throttle-inflight", milliseconds: 40) {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await store.dispatch(.appendItem("first"))
        }

        // Interval has elapsed, but the first operation is still in flight — ignored.
        try await Task.sleep(nanoseconds: 80_000_000)
        store.throttle(id: "throttle-inflight", milliseconds: 40) {
            await store.dispatch(.appendItem("overlap"))
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(store.state.items == [])

        // After in-flight work + lock release, a new leading-edge call is allowed.
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(store.state.items == ["first"])

        store.throttle(id: "throttle-inflight", milliseconds: 40) {
            await store.dispatch(.appendItem("after"))
        }

        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(store.state.items == ["first", "after"])
    }

    // MARK: - Retry

    @MainActor
    @Test func testRetrySucceedsOnFirstAttempt() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(id: "retry-first", maxRetries: 3, backoff: .constant(milliseconds: 10)) {
            await store.dispatch(.increment)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.state.count == 1)
    }

    @MainActor
    @Test func testRetryRecoversOnSecondAttempt() async throws {
        actor RetryTracker {
            private var attempt = 0
            func increment() -> Int {
                attempt += 1
                return attempt
            }
        }

        let tracker = RetryTracker()
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(id: "retry-recover", maxRetries: 3, backoff: .constant(milliseconds: 10)) {
            let attempt = await tracker.increment()
            if attempt < 2 {
                throw NSError(domain: "test", code: 1)
            }
            await store.dispatch(.increment)
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(store.state.count == 1)
    }

    @MainActor
    @Test func testRetryExhaustsAllAttempts() async throws {
        actor FailTracker {
            private var attempt = 0
            func increment() -> Int {
                attempt += 1
                return attempt
            }
            func current() -> Int { attempt }
        }

        let tracker = FailTracker()
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(id: "retry-exhaust", maxRetries: 2, backoff: .constant(milliseconds: 5)) {
            _ = await tracker.increment()
            throw NSError(domain: "test", code: 1)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // All attempts should have been made (1 initial + 2 retries = 3)
        let count = await tracker.current()
        #expect(count == 3)
        #expect(store.state.count == 0)
    }

    // MARK: - Timeout

    @MainActor
    @Test func testTimeoutDispatchesFallbackWhenOperationHangs() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(
            id: "timeout-test",
            timeoutMs: 50,
            fallback: { .timeoutFallback }
        ) {
            // This operation takes longer than timeout
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await store.dispatch(.increment)
        }

        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(store.state.message == "timeout")
        #expect(store.state.count == 0)  // Operation should not have completed
    }

    @MainActor
    @Test func testTimeoutLetsFastOperationComplete() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(
            id: "timeout-fast",
            timeoutMs: 200,
            fallback: { .timeoutFallback }
        ) {
            // This operation completes before timeout
            try? await Task.sleep(nanoseconds: 50_000_000)
            await store.dispatch(.increment)
        }

        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(store.state.count == 1)
        #expect(store.state.message == "")
    }

    @MainActor
    @Test func testTimeoutDoesNotInvokeFallbackWhenOperationWins() async throws {
        actor FallbackCounter {
            private var count = 0
            func increment() { count += 1 }
            func current() -> Int { count }
        }

        let counter = FallbackCounter()
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(
            id: "timeout-no-fallback",
            timeoutMs: 200,
            fallback: {
                await counter.increment()
                return .timeoutFallback
            }
        ) {
            try? await Task.sleep(nanoseconds: 20_000_000)
            await store.dispatch(.increment)
        }

        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(store.state.count == 1)
        #expect(store.state.message == "")
        #expect(await counter.current() == 0)
    }

    @MainActor
    @Test func testTimeoutSkippedWhenTimeoutMsIsNonPositive() async throws {
        let store = Store(initialState: TestState(), reducer: reducer)

        store.runTask(
            id: "timeout-disabled",
            timeoutMs: 0,
            fallback: { .timeoutFallback }
        ) {
            try? await Task.sleep(nanoseconds: 30_000_000)
            await store.dispatch(.increment)
        }

        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(store.state.count == 1)
        #expect(store.state.message == "")
    }

    // MARK: - BackoffStrategy

    @Test func testConstantBackoff() {
        let strategy = BackoffStrategy.constant(milliseconds: 100)

        #expect(strategy.delayNanoseconds(for: 0) == 100_000_000)
        #expect(strategy.delayNanoseconds(for: 5) == 100_000_000)
    }

    @Test func testExponentialBackoff() {
        let strategy = BackoffStrategy.exponential(baseMs: 100)

        #expect(strategy.delayNanoseconds(for: 0) == 100_000_000)
        #expect(strategy.delayNanoseconds(for: 1) == 200_000_000)
        #expect(strategy.delayNanoseconds(for: 2) == 400_000_000)
        #expect(strategy.delayNanoseconds(for: 3) == 800_000_000)
    }

    @Test func testExponentialBackoffCapsAtMax() {
        let strategy = BackoffStrategy.exponential(baseMs: 100, maxMs: 1_000)

        let delay = strategy.delayNanoseconds(for: 10)
        #expect(delay <= 1_000_000_000)
    }
}
