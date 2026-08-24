import Foundation

// MARK: - BackoffStrategy

/// Defines the retry backoff behavior for `runTask(maxRetries:backoff:operation:)`.
public enum BackoffStrategy: Sendable {
    /// Waits a constant amount of time between retries.
    ///
    /// - Parameter milliseconds: The fixed delay between retry attempts.
    case constant(milliseconds: Int)

    /// Waits exponentially longer between retries.
    ///
    /// The delay is calculated as `baseMs * 2^attempt`, capped at `maxMs`.
    ///
    /// - Parameters:
    ///   - baseMs: The base delay in milliseconds for the first retry.
    ///   - maxMs: The maximum delay in milliseconds (default: 10s).
    case exponential(baseMs: Int, maxMs: Int = 10_000)

    /// Returns the delay in nanoseconds for a given retry attempt (0-indexed).
    func delayNanoseconds(for attempt: Int) -> UInt64 {
        let ms: Int
        switch self {
        case .constant(let milliseconds):
            ms = milliseconds
        case .exponential(let baseMs, let maxMs):
            ms = min(baseMs * Int(pow(2.0, Double(attempt))), maxMs)
        }
        return UInt64(ms) * 1_000_000
    }
}

// MARK: - Debounce

extension Store {
    /// Root-store-only async primitive.
    ///
    /// `debounce` lives on `Store` rather than `StoreType` so all cancellable async work shares the
    /// same task registry anchored at the root state boundary.
    /// Debounces an asynchronous operation by the specified delay.
    ///
    /// If called multiple times with the same `id` before the delay elapses, only
    /// the most recent call's `operation` executes. This is ideal for search-as-you-type
    /// where you want to wait until the user stops typing.
    ///
    /// Internally uses `runTask(id:)` — the previous task with the same `id` is cancelled
    /// on each call, then the operation runs after the delay.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this debounce group. Reusing the same ID cancels
    ///         any pending debounced operation.
    ///   - milliseconds: The debounce delay in milliseconds.
    ///   - priority: The task priority.
    ///   - operation: The async operation to execute after the debounce delay.
    ///
    /// ## Example
    ///
    /// ```swift
    /// store.debounce(id: "search", milliseconds: 300) {
    ///     let results = await searchService.search(query)
    ///     guard !Task.isCancelled else { return }
    ///     await store.dispatch(.searchCompleted(results))
    /// }
    /// ```
    @discardableResult
    public func debounce(
        id: CancellationID,
        milliseconds: Int,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        runTask(id: id, priority: priority) {
            try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)

            guard !Task.isCancelled else { return }
            await operation()
        }
    }
}

// MARK: - Throttle

extension Store {
    /// Root-store-only async primitive.
    ///
    /// `throttle` stays on the root `Store` for the same reason as `runTask`: cancellation windows
    /// and task bookkeeping are centralized instead of being duplicated across scoped stores.
    /// Throttles an asynchronous operation so it executes at most once within the specified interval.
    ///
    /// Unlike debounce (which waits for a pause), throttle executes immediately on the first call
    /// and then ignores subsequent calls until the throttle lock is released.
    ///
    /// The lock lasts until **both** of these complete:
    /// 1. the leading-edge interval (`milliseconds`)
    /// 2. the in-flight `operation` started by this call
    ///
    /// That keeps leading-edge semantics while preventing a later call from starting overlapping
    /// work merely because the interval elapsed before a slow operation finished.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this throttle group.
    ///   - milliseconds: The throttle interval in milliseconds.
    ///   - priority: The task priority.
    ///   - operation: The async operation to execute.
    ///
    /// ## Example
    ///
    /// ```swift
    /// store.throttle(id: "scroll-track", milliseconds: 200) {
    ///     await store.dispatch(.trackScrollPosition(position))
    /// }
    /// ```
    @discardableResult
    public func throttle(
        id: CancellationID,
        milliseconds: Int,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        guard milliseconds > 0 else {
            return runTask(id: id, priority: priority) {
                await operation()
            }
        }

        let lockID = CancellationID(id.rawValue + ".throttle-lock")
        guard !hasManagedTask(id: lockID) else {
            return Task {}
        }

        let task = runTask(id: id, priority: priority) {
            await operation()
        }

        runTask(id: lockID, priority: priority) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
                }
                group.addTask {
                    await task.value
                }
                await group.waitForAll()
            }
        }

        return task
    }
}

// MARK: - Retry

extension Store {
    /// Root-store-only async primitive.
    ///
    /// Retry bookkeeping is intentionally anchored at the root `Store` so scoped stores keep a
    /// minimal view API while middleware owns side-effect orchestration.
    /// Runs an asynchronous operation with automatic retry on failure.
    ///
    /// If `operation` throws, it is retried up to `maxRetries` times with the
    /// specified `backoff` strategy between attempts. The task is cancelled on success.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this task.
    ///   - maxRetries: Maximum number of retry attempts (default: 3).
    ///   - backoff: The backoff strategy between retries (default: `.exponential(baseMs: 100)`).
    ///   - priority: The task priority.
    ///   - operation: The async throwing operation to execute.
    ///
    /// ## Example
    ///
    /// ```swift
    /// store.runTask(id: "sync", maxRetries: 3, backoff: .exponential(baseMs: 200)) {
    ///     let data = try await api.fetchData()
    ///     await store.dispatch(.dataLoaded(data))
    /// }
    /// ```
    @discardableResult
    public func runTask(
        id: CancellationID,
        maxRetries: Int,
        backoff: BackoffStrategy = .exponential(baseMs: 100),
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) -> Task<Void, Never> {
        runTask(id: id, priority: priority) {
            for attempt in 0...maxRetries {
                guard !Task.isCancelled else { return }

                do {
                    try await operation()
                    return
                } catch {
                    if attempt == maxRetries {
                        return
                    }

                    let delay = backoff.delayNanoseconds(for: attempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }
}

// MARK: - Timeout

private enum TimeoutRaceResult: Sendable {
    case completed
    case timedOut
}

extension Store where Action: Sendable {
    /// Root-store-only async primitive.
    ///
    /// Timeout fallback dispatch participates in the root store's task lifecycle and cancellation
    /// bookkeeping, so this helper is intentionally unavailable on `ScopedStore` / `StoreType`.
    /// Runs an asynchronous operation with a timeout. If the operation does not complete
    /// within the specified duration, a fallback action is dispatched.
    ///
    /// Semantics (intentionally restrained):
    /// 1. `operation` and the timeout timer race; the first finisher wins.
    /// 2. The loser is cancelled via structured concurrency (`cancelAll`).
    /// 3. `fallback` runs **only after** the timeout wins — it is not started in parallel.
    /// 4. Cancellation remains cooperative: `operation` must still `guard !Task.isCancelled`
    ///    before its own `dispatch`, or a late write can still land after fallback.
    ///
    /// When `timeoutMs <= 0`, the timeout race is skipped and `operation` runs as a normal
    /// `runTask(id:)`.
    ///
    /// - Parameters:
    ///   - id: A unique identifier for this task.
    ///   - timeoutMs: The timeout duration in milliseconds.
    ///   - fallback: A closure that produces the action to dispatch on timeout.
    ///   - priority: The task priority.
    ///   - operation: The async operation to execute.
    ///
    /// ## Example
    ///
    /// ```swift
    /// store.runTask(id: "fetch", timeoutMs: 5_000, fallback: { .fetchFailed(.timeout) }) {
    ///     let data = await api.fetchData()
    ///     guard !Task.isCancelled else { return }
    ///     await store.dispatch(.dataLoaded(data))
    /// }
    /// ```
    @discardableResult
    public func runTask(
        id: CancellationID,
        timeoutMs: Int,
        fallback: @escaping @Sendable () async -> Action,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> {
        guard timeoutMs > 0 else {
            return runTask(id: id, priority: priority) {
                await operation()
            }
        }

        let store = self
        return runTask(id: id, priority: priority) {
            let winner: TimeoutRaceResult = await withTaskGroup(of: TimeoutRaceResult.self) { group in
                group.addTask {
                    await operation()
                    return .completed
                }

                group.addTask {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                        return .timedOut
                    } catch {
                        // Sleep was cancelled because the operation finished first (or the
                        // outer task was cancelled). Do not treat that as a timeout win.
                        return .completed
                    }
                }

                let first = await group.next() ?? .completed
                group.cancelAll()
                await group.waitForAll()
                return first
            }

            guard winner == .timedOut, !Task.isCancelled else { return }

            let action = await fallback()
            guard !Task.isCancelled else { return }
            await store.dispatch(action)
        }
    }
}
