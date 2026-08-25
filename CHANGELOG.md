# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Architecture 5.0 (triangular)**: domain pure `Reducer` + `actor Store` + `Effect` system.
  - Products: `TGReduxKitCore`, `TGReduxKitRuntime`, `TGReduxKitUI`, `TGReduxKitTesting`, umbrella `TGReduxKit`.
  - `DependencyContext` injected into every reduce, with lightweight `DependencyKey` / typed subscript for app services.
  - `ObservableStore` (`@MainActor @Observable`) projects actor state for SwiftUI; forwards `withDependencies`.
  - Docs: `ADR_TRIANGULAR_ARCHITECTURE.md`, `MIGRATION_4_TO_5.md`, `EFFECT_GUIDE.md`, `ARCHITECTURE_DI_AND_SHOPPING_MODULE.md`, review union notes.

### Changed
- **Breaking**: `Reducer` is a nonisolated `struct` returning `Effect`; no longer `@MainActor` function typealias.
- **Breaking**: Runtime `Store` is an `actor`; UI uses `ObservableStore`.
- **Breaking**: Onion `Middleware` is no longer the primary async path; use `Effect` from reducers.
- **Breaking**: `State` / `Action` must be `Sendable`.
- Demo: single `Shopping` module (no Domain/Feature split); services via `DependencyKey` function values instead of `ShoppingDependencies` protocols.

### Removed
- 4.x Middleware pipeline, `ScopedStore`, Store-level `runTask`/`debounce`/`throttle`/`timeout` API surface, and in-tree time-travel UI (first 5.0 cut).

## [4.0.1] - 2026-08-25

### Changed
- **Async / Throttle**: `throttle` 的锁现在覆盖「节流窗口 ∪ 本次 in-flight operation」。
  - 窗口结束后若首次操作仍在运行，后续 leading-edge 调用继续被忽略，避免叠加工。
- **Async / Timeout**: `runTask(id:timeoutMs:fallback:)` 改为先决出竞速胜负，仅在超时获胜后调用 `fallback`。
  - 计时器被取消（operation 先完成）时不再误判为超时。
  - `timeoutMs <= 0` 时跳过超时竞速，行为与普通 `runTask(id:)` 一致。
- **Docs**: 在 `ASYNC_RACE_AND_CANCELLATION.md` / `ADVANCED_USAGE.md` 中明确 throttle 锁与 timeout 协作取消边界。
- **Docs**: 新增 `DEFAULT_ACTOR_ISOLATION_AND_REDUX.md`，说明 Xcode 默认 MainActor 与 Redux 领域模型的边界与最佳实践（优先拆 Domain 模块，而非逐类型标 `nonisolated`）。
- **Demo**: 抽出本地包 `ShoppingDomain`（无 MainActor 默认）承载 State / Action / Model / 服务；App 保留 MainActor 默认，只保留 Reducer / Middleware / View。
  - Demo 改为本地依赖 `TGNavigationStack`，便于对齐导航包最新严格并发改动。

### Fixed
- **Tests**: 新增回归用例，覆盖 throttle in-flight 锁、timeout 获胜前不调用 fallback、非正 `timeoutMs` 短路。

## [4.0.0] - 2026-08-25

### Added
- **SwiftUI / Ergonomics**: 为 `Store.binding` 和 `ScopedStore.binding` 新增 `KeyPath` 读取重载。
  - `store.binding(get: \.name, send: ...)` 现在可直接使用，减少样板闭包。

### Changed
- **Core / Performance**: `Store` 在初始化时预组合 middleware dispatch 管道，避免每次 `dispatch(_:)` 重建 onion 闭包链。
- **Observation / Equatable**: `Store` 与 `ScopedStore` 现在会在 `State: Equatable` 且值未变化时跳过多余赋值和子 store 通知。
  - 非 `Equatable` state 继续保持原有通知语义。
- **SwiftUI / API Surface**: 新增 `StoreType` 协议，统一 `Store` / `ScopedStore` 的最小公共接口。
  - `binding` 现在基于 `StoreType` 提供，`provideStore` 也收敛为单个泛型重载。
  - View 层可以对 root/scoped store 复用同一套 `state` / `dispatch` / `binding` 接口。
- **Async Boundary**: 明确 `StoreType` 只统一 View 层同步 API，`runTask` / `debounce` / `throttle` / retry / timeout 继续保持为 root `Store` 能力。
  - `ScopedStore` 不转发任务生命周期 API，异步副作用统一留在 root store 的 middleware / 协调层。
- **Testing / DX**: `TestStore` 断言失败从 `fatalError` 切换为抛出 `TestStoreAssertionError`。
  - `send(_:expect:)`、`assert(_:_:)`、`assert(equals:)` 现在可直接接入 Swift Testing / XCTest 的错误报告。
- **Docs**: 新增 `Docs/README.md` 作为文档分层入口，并将 README 的文档索引收敛为「接入指南 / 架构分析 / 审阅与维护」三层。
- **Docs**: Demo、文档与 `CLAUDE.md` 模块说明对齐独立导航仓库。

### Removed
- **Breaking / Navigation**: 导航状态模型与 SwiftUI 适配层已整体迁移到独立仓库 [`TGNavigationStack`](https://github.com/tangzzz-fan/TGNavigationStack)（`1.0.0`）。
  - 移除 `TGReduxKit` 内的 `TGRoute`、`NavigationState`、`NavigationAction`、`navigationReducer`。
  - 移除 `TGReduxKitNavigation` product / target 及其中的 `TGNavigationStack`。
  - 独立包中的 `TGNavigationStack` 继续保证单向数据流：path / dismiss 通过 `NavigationAction` 回 reducer。
  - 接入方需额外添加依赖：`.package(url: "https://github.com/tangzzz-fan/TGNavigationStack", from: "1.0.0")`。
  - Demo 工程已改为依赖 `TGNavigationStack` `1.0.0`。

## [3.0.0] - 2026-08-25

### Added
- **Docs**: 新增 `Docs/ASYNC_RACE_AND_CANCELLATION.md`，细化异步竞态（问题 A）与任务生命周期取消（问题 B）。
- **Docs**: 新增 `Docs/WHY_REDUX_ADOPTION.md`，说明为何转向轻量 Redux、设计优势与团队内采纳路径。

### Changed
- **Core / Strict Concurrency**: `Reducer` 正式收口到 `@MainActor`，与 `Store`、`Middleware` 对齐为 Swift 6+ 严格并发优先模型。
  - `combineReducers(_:)`、`pullback(_:state:extract:)` 和 `navigationReducer` 同步标注为 `@MainActor`。
  - `pullback` 的 `extract` 闭包也同步收口到 `@MainActor`，避免在组合 reducer 时触发 Swift 6 数据竞争诊断。
  - 仓库内测试与 Demo 的 reducer 声明统一改为 `Reducer<...>`，不再继续使用裸 `(inout State, Action) -> Void` 类型。
- **Core / API Naming**: 将公开的 `Dispatch<Action>` 重命名为 `ActionDispatcher<Action>`，避免与系统 `Dispatch` 模块命名冲突。
- **Documentation**: 更新 `Reducer` / `Middleware` 注释与示例，明确主 actor 边界与异步副作用回流方式。

### Fixed
- **Async Primitives / Throttle**: 修复 `throttle(id:milliseconds:operation:)` 实际未执行节流的问题。
  - 现在同一窗口内的重复调用会被忽略，窗口结束后才允许下一次触发。
- **Core / Task Lifecycle**: 修复 `runTask(id:)` 在同 ID 替换时旧任务与新任务可能重叠运行的问题。
  - 新任务会等待被取消的旧任务完成清理后再开始。
  - 直接取消返回的 `Task` 句柄时，也会同步清理内部 `managedTasks` 条目。
- **Core / Observer Propagation**: 修复父/子 store 在通知 scoped observers 时的重入覆盖问题，改为基于快照遍历并清理失效 observer。
- **Core / Scope Lifecycle**: 修复 `scope(state:action:)` 在父 store 生命周期结束后通过 `fatalError` 崩溃的问题，改为由 scoped store 持有稳定状态来源。
- **Debug / Time Travel**: 修复 `TimeTravelRecorder` 多项边界行为。
  - `maxEntries` 裁剪后 `index` 现在保持全局单调递增，避免 SwiftUI `ForEach` identity 冲突。
  - `snapshot(at:)` 改为按逻辑 timeline index 读取，而非数组位置。
  - `initialState` 独立保存，不再依赖当前 entries 的首项。
  - `maxEntries` 对负值输入会钳制并立即裁剪。
  - `exportJSON()` 现在会传播 action 编码失败，而不是静默降级。
- **Tests**: 新增回归测试，覆盖 throttle 窗口行为、task 串行化与句柄取消清理、time-travel 裁剪/index/导出失败等边界场景。

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
