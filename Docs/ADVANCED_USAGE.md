# 高级用法

## 1. Scoped Store

```swift
struct ProfileState {
    var name = ""
}

struct AppState {
    var profile = ProfileState()
}

enum ProfileAction {
    case updateName(String)
}

enum AppAction {
    case profile(ProfileAction)
}

let profileStore = store.scope(
    state: \.profile,
    action: AppAction.profile
)
```

子视图可以只依赖 `ScopedStore<ProfileState, ProfileAction>`，避免直接耦合根状态树。

`ScopedStore` 只镜像 root store 的同步 View API。`runTask`、`debounce`、`throttle`、retry / timeout 等异步原语仍然只属于 root `Store`，这样任务生命周期和取消语义都集中在同一个边界内。

## 2. 处理异步操作

Reducer 必须保持纯净，副作用应在 **Middleware** 中处理。

这里的约束是明确的：**异步副作用只允许 root `Store` 持有**。View 可以统一依赖 `StoreType`，但真正启动任务的地方应该在 root store 所在的 middleware / 协调层。

```swift
enum AppAction {
    case fetchUser
    case userLoaded(String)
    case loading(Bool)
}

let apiMiddleware: Middleware<AppState, AppAction> = { store, action, next in
    next(action)

    if case .fetchUser = action {
        store.runTask(id: "fetch-user") {
            await store.dispatch(.loading(true))
            try? await Task.sleep(nanoseconds: 1_000_000_000)

            guard !Task.isCancelled else { return }

            let user = "User-" + String(Int.random(in: 1...100))
            await store.dispatch(.userLoaded(user))
            await store.dispatch(.loading(false))
        }
    }
}
```

## 3. 声明式异步原语

TGReduxKit 提供了防抖、节流、重试、超时等声明式原语：

**Debounce（防抖）** — 适合搜索框输入：

```swift
store.debounce(id: "search", milliseconds: 300) {
    let results = await searchService.search(query)
    guard !Task.isCancelled else { return }
    await store.dispatch(.searchCompleted(results))
}
```

**Throttle（节流）** — 适合滚动追踪、快速点击：

```swift
store.throttle(id: "scroll-track", milliseconds: 200) {
    await store.dispatch(.trackPosition(position))
}
```

**Retry（重试）** — 自动重试失败的请求：

```swift
store.runTask(id: "sync", maxRetries: 3, backoff: .exponential(baseMs: 200)) {
    let data = try await api.fetchData()
    await store.dispatch(.dataLoaded(data))
}
```

**Timeout（超时）** — 超时后自动 fallback：

```swift
store.runTask(id: "fetch", timeoutMs: 5_000, fallback: { .fetchFailed(.timeout) }) {
    let data = await api.fetchData()
    guard !Task.isCancelled else { return }
    await store.dispatch(.dataLoaded(data))
}
```

## 4. 取消同类旧任务

```swift
store.runTask(id: "search") {
    try? await Task.sleep(nanoseconds: 300_000_000)
    guard !Task.isCancelled else { return }
    await store.dispatch(.performSearch)
}

store.cancelTask(id: "search")
```

## 5. 使用 TestStore 测试 Reducer

`TestStore` 是纯 reducer 的同步测试工具，不需要运行 App 或等待异步操作：

```swift
import Testing
@testable import TGReduxKit

@Test func counterFlow() throws {
    let store = TestStore(initialState: CounterState(), reducer: counterReducer)

    // send + expect 合并断言
    try store.send(.increment, expect: CounterState(count: 1))

    // 逐步 send + assert
    store.send(.increment)
    store.send(.decrement)
    try store.assert(equals: CounterState(count: 1))

    // 自定义 predicate 断言
    store.send(.setMessage("Done"))
    try store.assert("state should match") { state in
        state.count == 1 && state.message == "Done"
    }

    // 检查完整状态历史
    let history = store.replayHistory()
    #expect(history.count == 4) // 初始状态 + 3 次 send
}
```

`TestStore` 的断言失败现在会抛出结构化的 `TestStoreAssertionError`，能更自然地接入 Swift Testing / XCTest 的失败报告，而不会通过 `fatalError` 直接终止整个测试进程。

## 6. 调试中间件

```swift
let store = Store(
    initialState: AppState(),
    reducer: appReducer,
    middlewares: [
        actionLoggingMiddleware(),
        stateDiffMiddleware()
    ]
)
```

## 7. 时间旅行调试（v2.0）

挂载 `timeTravelMiddleware` 录制每个 Action 前后的 State 快照：

```swift
let recorder = TimeTravelRecorder<AppState, AppAction>()
let store = Store(
    initialState: AppState(),
    reducer: appReducer,
    middlewares: [timeTravelMiddleware(recorder: recorder)]
)

store.dispatch(.increment)
store.dispatch(.decrement)

// 回溯时间线
for entry in recorder.entries {
    print("#\(entry.index): \(entry.action) → \(entry.stateAfter)")
}

// 跳转到任意快照
let earlier = recorder.snapshot(at: 1)
```

`TimelineInspector` 提供 SwiftUI debug 视图，嵌入 App 的 `#if DEBUG` 菜单即可浏览完整时间线。

> 完整使用指南（购物 App + 车载 App 场景）见 [时间旅行调试指南](TIME_TRAVEL_GUIDE.md)。

## 8. 与依赖注入容器协作

TGReduxKit 不需要内建 DI 容器。更合适的方式是让 Factory、Swinject、Resolver 一类容器在框架外解析依赖，再把依赖传入 middleware 工厂。

```swift
protocol UserRepository: Sendable {
    func fetchUser() async throws -> User
}

struct AppDependencies: Sendable {
    var userRepository: any UserRepository
}

func makeUserMiddleware(
    dependencies: AppDependencies
) -> Middleware<AppState, AppAction> {
    { store, action, next in
        next(action)

        guard case .loadUser = action else { return }

        store.runTask(id: "load-user") {
            guard let user = try? await dependencies.userRepository.fetchUser() else {
                return
            }

            await store.dispatch(.userLoaded(user))
        }
    }
}

let dependencies = AppDependencies(
    userRepository: container.userRepository()
)

let store = Store(
    initialState: AppState(),
    reducer: appReducer,
    middlewares: [
        makeUserMiddleware(dependencies: dependencies)
    ]
)
```

这种模式把职责分得很清楚：

- TGReduxKit 负责状态流、作用域和副作用生命周期。
- DI 容器负责解析 service、repository、client。
- View 和 reducer 不直接依赖具体容器实现。

## 9. 与 Feature Flag 库协作

Feature Flag 更适合作为依赖源，而不是 Store 内建能力。推荐做法是由 Feature Flag SDK 或封装服务提供 flag 快照，再通过 middleware 或应用启动流程把结果转换成普通 action。

```swift
protocol FeatureFlagServicing: Sendable {
    func boolValue(for key: String) async -> Bool
}

struct AppState {
    var flags = FlagsState()
}

struct FlagsState {
    var isNewCheckoutEnabled = false
}

enum AppAction {
    case appLaunched
    case flagsLoaded(isNewCheckoutEnabled: Bool)
}

func makeFeatureFlagMiddleware(
    featureFlags: any FeatureFlagServicing
) -> Middleware<AppState, AppAction> {
    { store, action, next in
        next(action)

        guard case .appLaunched = action else { return }

        store.runTask(id: "load-feature-flags") {
            let isNewCheckoutEnabled = await featureFlags.boolValue(for: "new_checkout")
            await store.dispatch(
                .flagsLoaded(isNewCheckoutEnabled: isNewCheckoutEnabled)
            )
        }
    }
}
```

推荐的职责边界：

- Feature Flag 库负责远端拉取、缓存和分流规则。
- TGReduxKit 负责把 flag 结果转换成可追踪的状态与 action。
- 配置看板类 View 可以读取 `FeatureFlagsState`，业务 View 更推荐读取 reducer 映射后的派生展示状态。
- Demo 中的完整落地方案见 [Feature Flag 指南](FEATURE_FLAG_GUIDE.md)。

常见结合方式：

- **启动期预加载**：App 启动后拉取 flag，驱动首页模块开关。
- **按模块注入**：把某个 feature 的 flag service 注入对应 middleware builder。
- **实验治理**：将实验分组结果写入 state，配合 analytics middleware 统一上报。
- **降级保护**：远端关闭某个高风险功能时，通过 action 立即收敛到稳定 UI。
