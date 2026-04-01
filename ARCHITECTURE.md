# TGReduxKit 架构设计文档

## 1. 概述

TGReduxKit 是一个专为 SwiftUI 设计的单向数据流（Redux）状态管理框架。
目标是利用 iOS 17+ 引入的 Swift Observation 框架 (`@Observable`) 实现高效响应式更新，同时保持比 TCA 更轻的 API 与工程约束。

## 2. 核心原则

- **单一数据源 (Single Source of Truth)**: 应用的所有状态存储在一个对象树 (`State`) 中。
- **状态只读 (State is Read-Only)**: 唯一改变状态的方法是触发一个 `Action`。
- **纯函数修改 (Changes are made with Pure Functions)**: 使用 `Reducer` 纯函数来描述 Action 如何转换 State。
- **主线程一致性 (MainActor Consistency)**: `Store`、`ScopedStore`、状态读取和 `dispatch` 统一收敛到主线程。
- **局部状态暴露 (Feature Scoped Access)**: 通过 `ScopedStore` 将根状态映射为 Feature 状态，避免 View 直接依赖完整状态树。
- **轻量副作用管理 (Lightweight Effects)**: 保留同步 middleware 模型，异步任务通过 `Task` 和 `CancellationID` 管理。

## 3. 模块设计

### 3.1 Core (核心层)

#### State
- 定义：应用的状态模型。
- 类型：通常是 `struct`，必须遵循 `Equatable` 以便进行比较（尽管 Observation 机制可能不需要显式的 Equatable 来触发更新，但用于 diff 和调试很有用）。

#### Action
- 定义：描述发生了什么。
- 类型：`protocol` 或 `enum`。建议使用 `enum` 来定义具体的动作集合。

#### Reducer
- 定义：纯函数，接收当前 `State` 和 `Action`，同步更新状态。
- 签名：`(inout State, Action) -> Void`。
- 不支持返回式 reducer。

#### Store
- 定义：保存 State，提供 `dispatch` 方法，连接 Reducer。
- 实现：使用 `@MainActor @Observable` 标记的 `class`。
- 职责：
  - 持有 `state`。
  - 接收 `action`。
  - 运行 `middleware`。
  - 执行 `reducer` 更新 `state`。
  - 创建 `ScopedStore`。
  - 管理带 `CancellationID` 的异步任务。

#### ScopedStore
- 定义：从根 `Store` 或上级 `ScopedStore` 派生的 Feature 级 Store。
- 职责：
  - 暴露局部 `state`。
  - 将局部 `Action` 映射回父级 `Action`。
  - 支持继续向下 `scope`。

#### Middleware
- 定义：在 Action 到达 Reducer 之前/之后执行副作用（如网络请求、日志、路由）。
- 签名：`@MainActor (Store<State, Action>, Action, @escaping Dispatch<Action>) -> Void`。
- middleware 本身保持同步，异步操作在内部通过 `Task` 或 `store.runTask` 启动。

#### Cancellation
- `CancellationID` 用于识别可取消任务。
- `Store.runTask(id:)` 会在相同 ID 下自动取消旧任务。
- `Store.cancelTask(id:)` 与 `Store.cancelAllTasks()` 用于主动清理任务。

### 3.2 SwiftUI Integration (集成层)

#### StoreProvider / Environment
- 利用 SwiftUI 的 `Environment` 注入 `Store` 或 `ScopedStore`。
- 提供 `provideStore` 扩展统一注入入口。

#### Binding
- `Store.binding` 与 `ScopedStore.binding` 用于把状态字段桥接成 `Binding`。
- View 通过 `binding(get:send:)` 与 action 系统保持单向数据流。

### 3.3 Debugging (调试层)

- `actionLoggingMiddleware()` 用于输出 action 轨迹。
- `stateDiffMiddleware()` 用于输出 action 前后的 state 描述。

## 4. 详细设计 (iOS 17+ / Swift 5.9+)

### Store 定义

```swift
@MainActor
@Observable
public final class Store<State, Action> {
    public private(set) var state: State
    private let reducer: (inout State, Action) -> Void
    private let middlewares: [Middleware<State, Action>]

    public init(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Void,
        middlewares: [Middleware<State, Action>] = []
    ) { ... }

    public func dispatch(_ action: Action) {
        // Run middleware pipeline
        // Apply reducer
        // Notify scoped stores
    }

    public func scope<ChildState, ChildAction>(
        state: KeyPath<State, ChildState>,
        action: @escaping (ChildAction) -> Action
    ) -> ScopedStore<ChildState, ChildAction> { ... }

    public func runTask(
        id: CancellationID? = nil,
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async -> Void
    ) -> Task<Void, Never> { ... }
}
```

### ScopedStore 定义

```swift
@MainActor
@Observable
public final class ScopedStore<State, Action> {
    public private(set) var state: State

    public func dispatch(_ action: Action)

    public func scope<ChildState, ChildAction>(
        state: KeyPath<State, ChildState>,
        action: @escaping (ChildAction) -> Action
    ) -> ScopedStore<ChildState, ChildAction>
}
```

### 异步处理

使用 Swift Concurrency (`Task`) 在 middleware 中处理副作用。

推荐优先使用：

```swift
store.runTask(id: "load-items") {
    let items = await repository.loadItems()
    guard !Task.isCancelled else { return }
    await store.dispatch(.itemsLoaded(items))
}
```

而不是在项目中手写零散且无法取消的匿名任务。

## 5. 目录结构

```
Sources/
  TGReduxKit/
    Core/
      CancellationID.swift
      DebugMiddleware.swift
      ScopedStore.swift
      Store.swift
      Reducer.swift
      Middleware.swift
    SwiftUI/
      Store+Binding.swift
      StoreProvider.swift
```

## 6. 迁移与兼容性

- 最低支持：iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0
- 依赖：无第三方依赖，仅使用 Swift 标准库和 SwiftUI。
