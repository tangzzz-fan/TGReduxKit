# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Docs**: 新增 `Docs/ASYNC_RACE_AND_CANCELLATION.md`，细化异步竞态（问题 A）与任务生命周期取消（问题 B）。
- **Docs**: 新增 `Docs/WHY_REDUX_ADOPTION.md`，说明为何转向轻量 Redux、设计优势与团队内采纳路径。

## [2.0.0] - 2026-07-03

### Added
- **Debug / Time Travel**: 新增 `TimeTravelRecorder` + `timeTravelMiddleware`。
  - 以 middleware 形式录制 action 时间线和 state 快照（before/after）。
  - 支持 `isRecording` 开关、`maxEntries` 上限、`snapshot(at:)` 跳转、`filter(where:)` 筛选。
  - JSON 导出（State/Action 遵循 Codable 时）。
  - 生产环境 zero-cost——不挂载 middleware 不产生任何开销。
- **Debug / TimelineInspector**: 新增 SwiftUI debug View。
  - 显示 action 列表（index + timestamp）。
  - 点击任一 entry 查看 before/after State 详情。
  - 内建 Pause / Resume / Clear 控件。
- **Tests**: 新增 `TimeTravelTests`（9 个测试用例），覆盖录制、跳转、筛选、暂停、上限裁剪、清空、JSON 导出、跨 Feature 时间线。
- **Docs**: 新增 `docs/TIME_TRAVEL_GUIDE.md`，覆盖购物 App 和车载 App 两个场景的时间旅行调试用法。

## [1.4.1] - 2026-07-03

### Changed
- **Demo / Redux.swift**: `shoppingReducer` 从手写 switch 重构为 `combineReducers + pullback` 组合式写法。
  - 新增三个独立的 Feature reducer（`catalogReducer` / `cartReducer` / `featureFlagsReducer`）。
  - 新增 `crossCuttingReducer` 集中处理子 Reducer 无法覆盖的根级逻辑（Flag→展示字段映射、多子 State 联动、路由/Deep Link）。
  - 新增详细的中文注释解释 `pullback` 的使用场景及其边界。

### Added
- **Documentation / README**: 新增「为什么需要 pullback」章节。
  - 引用 Demo 场景说明子 Reducer 何时需要父级介入。
  - 解释 `pullback` 与 `crossCuttingReducer` 的角色分工。

## [1.4.0] - 2026-07-03

### Added
- **Core / Reducer Composition**: 新增 `combineReducers(_:)` 和 `pullback(_:state:extract:)`。
  - `combineReducers` 按顺序合并多个 reducer，每个 reducer 自己决定是否响应当前 action。
  - `pullback` 将子 reducer 的 `(ChildState, ChildAction)` 提升为 `(ParentState, ParentAction)`，只在 extract 闭包返回非 nil 时运行。
  - 零成本抽象——纯 free function，不引入协议或 CasePath。
- **Tests**: 新增 `ReducerCompositionTests`（10 个测试用例），覆盖：pullback 隔离性、combineReducers 执行顺序、深度嵌套、空列表/单 reducer、多 extract pattern、导航组合、shopping 完整流程。
- **Documentation**: README「模块化 Reducer」章节更新为 `combineReducers` + `pullback` 组合式写法。

## [1.3.1] - 2026-07-03

### Added
- **Tests**: 新增 `CrossFeatureTests`（5 个测试用例），覆盖 README 中三种跨 Feature 通信模式：
  - 模式一：父级 Middleware 转发（cart add → recommendations refresh）
  - 模式二：Reducer 内联联动（catalog/cart update → recommendations 同步更新）
  - 模式三：显式协调 Action（跨 Feature 边界编译期约束）
  - 三种模式共存验证

## [1.3.0] - 2026-07-03

### Added
- **Core / Error Handling**: 新增错误处理统一通道。
  - `ErrorAction` 协议 — Action 中的错误 case 可遵循该协议标记错误来源。
  - `store.runTask(id:catching:operation:)` — catch 异步错误后自动转为 action 回流。
  - `errorReportingMiddleware(extract:reporter:)` — 全局错误拦截上报 middleware（支持自定义 extract 闭包）。
  - `errorReportingMiddleware(reporter:)` — 便捷版本，适用于 Action 类型直接遵循 `ErrorAction` 的场景。
- **Documentation / README**:
  - 新增「跨 Feature 通信」章节：三种模式（父级 middleware 转发/reducer 内联联动/显式协调 action）及适用场景。
  - 新增「错误处理指南」章节：`runTask(catching:)` 业务错误恢复 + `errorReportingMiddleware` 全局上报。
- **CI**: 新增 `.github/workflows/ci.yml`，包含 macOS build/test + iOS Simulator build + SwiftLint。
- **Tests**: 新增 `ErrorHandlingTests`（6 个测试用例），覆盖 catching、silent drop、cancellation 不触发、extract 匹配/跳过。

## [1.2.0] - 2026-07-03

### Added
- **Testing / TestStore**: 新增 `TestStore<State, Action>` 用于 reducer 的同步测试。
  - `send(_:)` 同步派发 action，记录 state 历史。
  - `send(_:expect:)` 派发 action 并断言期望状态。
  - `assert(equals:)` 断言当前状态与期望值一致。
  - `assert(_:_:)` 基于 predicate 的自定义断言。
  - `reset(to:)` 重置 TestStore 到新初始状态。
  - `replayHistory()` 回放完整的状态变更历史。
- **Core / Async Primitives**: 新增声明式异步原语，全部基于现有 `runTask(id:)` 机制。
  - `debounce(id:milliseconds:operation:)` 防抖执行，同 ID 自动取消旧任务。
  - `throttle(id:milliseconds:operation:)` 节流执行，确保在间隔内只执行一次。
  - `runTask(id:maxRetries:backoff:operation:)` 带重试的异步任务，支持 `.constant` 和 `.exponential` 两种退避策略。
  - `runTask(id:timeoutMs:fallback:operation:)` 带超时的异步任务，超时后自动 dispatch fallback action。
  - `BackoffStrategy` 枚举，支持 constant 和 exponential（可设置 maxMs 上限）。
- **Tests**: 新增 `TestStoreTests`（14 个测试用例）和 `AsyncPrimitivesTests`（12 个测试用例）。

### Fixed
- 修复 `TGNavigationStack` 在 macOS 上无法编译的问题（`fullScreenCover` 仅限 iOS/tvOS）。

## [1.1.0] - 2026-04-02

### Added
- **Documentation**
  - Added a standalone Feature Flag integration article covering architecture boundaries, module design, and a maintenance-oriented rollout plan.
- **Demo**
  - Added a comprehensive Feature Flag example to `TGReduxKitDemo` with startup loading, manual refresh, scoped state consumption, and UI branching.
- **Tests**
  - Added demo tests covering catalog visibility derivation under search and Feature Flag combinations.

## [1.0.0] - 2026-04-02

### Changed
- **Release**
  - Promoted TGReduxKit to `1.0.0` to reflect a stabilized public API centered on `@MainActor Store`, `ScopedStore`, lightweight task cancellation, and documented integration patterns.

### Added
- **Core / Scope**
  - Added `ScopedStore<State, Action>` for feature-level state/action projection.
  - Added nested `scope(state:action:)` support from both `Store` and `ScopedStore`.
- **Core / Cancellation**
  - Added `CancellationID` as a lightweight task identity.
  - Added `runTask(id:priority:operation:)`, `cancelTask(id:)`, and `cancelAllTasks()` on `Store`.
- **Core / Debug**
  - Added `actionLoggingMiddleware()` for action tracing.
  - Added `stateDiffMiddleware()` for before/after state inspection.
- **SwiftUI**
  - Added `provideStore(_:)` overload for `ScopedStore`.
  - Added `ScopedStore.binding(get:send:)` to keep feature views on the same binding API.
- **Tests**
  - Added coverage for scoped store synchronization, nested scopes, task cancellation, and debug middleware.

### Changed
- **Core / Concurrency**
  - Moved `Store` to `@MainActor` to unify state reads, writes, and dispatch on the main thread.
  - Moved `Dispatch` and `Middleware` execution semantics to `@MainActor`.
  - Removed the previous `NSLock`-based mixed concurrency path in favor of a single actor-isolated model.
- **Core / State Flow**
  - Store dispatch now notifies scoped stores after reducer execution so feature stores remain synchronized with root state.

### Documentation
- **README**
  - Updated the public guide to match the actual reducer and middleware model.
  - Added scoped store, cancellation, and debug middleware examples.
  - Added a dependency injection integration example that keeps DI containers outside the store boundary.
- **ARCHITECTURE**
  - Rewrote the architecture description around `@MainActor Store`, `ScopedStore`, and lightweight cancellation.

### Demo
- **TGReduxKitDemo**
  - Updated the demo app to use `ScopedStore` for catalog and cart features.
  - Added a debounced product search flow implemented with `store.runTask(id:)`.
  - Added a dependency-driven middleware builder example through `ShoppingDependencies`.
  - Switched the demo logging example to the built-in `actionLoggingMiddleware()`.

## [0.0.2] - 2026-01-14

### Changed
- Moved `TGReduxKitDemo` into `Examples/` directory for better project structure.
- Updated demo project dependencies to reference the local package correctly.
- Removed obsolete `CounterAppExample.swift`.

## [0.0.1] - 2026-01-11

### Added
- **Core**: Initial implementation of `Store`, `Middleware`, and `Reducer`.
- **SwiftUI**: Added `StoreProvider` (via `.provideStore`) and `Store.binding` helper.
- **Concurrency**: Full support for Swift 6 strict concurrency checks (`Sendable` conformance).
- **Documentation**:
  - Comprehensive API documentation (DocC).
  - Architecture diagram and usage guide in `README.md`.
  - Advanced usage examples (Async Middleware, Modular Reducers).
- **Examples**: Added `CounterAppExample` in `Examples/` directory.
- **CI/Quality**: Added `.swiftlint.yml` configuration.
