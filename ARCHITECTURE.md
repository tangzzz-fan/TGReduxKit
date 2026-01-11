# TGReduxKit 架构设计文档

## 1. 概述
TGReduxKit 是一个专为 SwiftUI 设计的单向数据流（Redux）状态管理框架。
目标是利用 iOS 17+ 引入的 Swift Observation 框架 (`@Observable`) 来实现高效、响应式的状态更新，避免 Combine `ObservableObject` 的一些样板代码和性能开销。

## 2. 核心原则
- **单一数据源 (Single Source of Truth)**: 应用的所有状态存储在一个对象树 (`State`) 中。
- **状态只读 (State is Read-Only)**: 唯一改变状态的方法是触发一个 `Action`。
- **纯函数修改 (Changes are made with Pure Functions)**: 使用 `Reducer` 纯函数来描述 Action 如何转换 State。

## 3. 模块设计

### 3.1 Core (核心层)

#### State
- 定义：应用的状态模型。
- 类型：通常是 `struct`，必须遵循 `Equatable` 以便进行比较（尽管 Observation 机制可能不需要显式的 Equatable 来触发更新，但用于 diff 和调试很有用）。

#### Action
- 定义：描述发生了什么。
- 类型：`protocol` 或 `enum`。建议使用 `enum` 来定义具体的动作集合。

#### Reducer
- 定义：纯函数，接收当前 `State` 和 `Action`，返回新的 `State`。
- 签名：`(inout State, Action) -> Void` 或 `(State, Action) -> State`。
  - 为了性能和 Swift 的值语义，推荐使用 `inout` 方式：`Reduce<State, Action> = (inout State, Action) -> Void`。

#### Store
- 定义：保存 State，提供 `dispatch` 方法，连接 Reducer。
- 实现：使用 `@Observable` 宏标记的 `class`。
- 职责：
  - 持有 `state`。
  - 接收 `action`。
  - 运行 `middleware`。
  - 执行 `reducer` 更新 `state`。

#### Middleware
- 定义：在 Action 到达 Reducer 之前/之后执行副作用（如网络请求、日志、路由）。
- 签名：`(Store, Action) async -> Action?` 或者更经典的 `(Store) -> (@escaping Dispatch) -> (Action) -> Void`。
- 考虑到 Swift Concurrency，我们将设计基于 `async/await` 的 Middleware。

### 3.2 SwiftUI Integration (集成层)

#### StoreProvider / Environment
- 利用 SwiftUI 的 `Environment` 注入 Store。
- 提供 `View` 扩展方便获取 Store。

## 4. 详细设计 (iOS 17+ / Swift 5.9+)

### Store 定义
```swift
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
        // Run middlewares
        // Run reducer
    }
}
```

### 异步处理 (Side Effects)
使用 Swift Concurrency (`Task`) 在 Middleware 中处理副作用。
Middleware 可以返回一个 `Action` 流或者直接 dispatch 新的 action。

## 5. 目录结构
```
Sources/
  TGReduxKit/
    Core/
      Store.swift
      Reducer.swift
      Middleware.swift
    SwiftUI/
      StoreProvider.swift
```

## 6. 迁移与兼容性
- 最低支持：iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0
- 依赖：无第三方依赖，仅使用 Swift 标准库和 SwiftUI。
