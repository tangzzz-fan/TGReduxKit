# TGReduxKit Swift 6 严格并发收口

## 背景

TGReduxKit 现在明确面向 Swift 6+ 的严格并发环境。

本轮收口前，库的并发语义并不完全闭合：

1. `Store` 是 `@MainActor`
2. `Middleware` 是 `@MainActor`
3. `Reducer` 却仍是普通闭包

这会导致模块级 reducer 常量在 Swift 6 严格并发下触发诊断，也会让公开 API 契约和真实运行模型分叉。

## 原始问题

问题的本质不是“某个 reducer 能不能跑”，而是：

> 状态流已经运行在 MainActor 上，但类型系统没有完整承认这一点。

典型表现是：

```swift
public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = ...
```

当 `Reducer` 不是 actor-isolated 时，Swift 6 会把这类全局常量视为非并发安全值。

## 这次的收口方式

### 1. Reducer 正式收口到 MainActor

```swift
public typealias Reducer<State, Action> = @MainActor (inout State, Action) -> Void
```

### 2. 组合器同步收口

以下构件也一起改为 `@MainActor`：

1. `combineReducers(_:)`
2. `pullback(_:state:extract:)`
3. `pullback` 的 `extract` 闭包
4. `navigationReducer`

### 3. 仓库内部声明统一对齐

Demo、测试、辅助 reducer 声明全部改回 `Reducer<...>`，不再继续使用裸 `(inout State, Action) -> Void` 类型。

## 新的架构边界

修正后，TGReduxKit 的核心边界是：

1. `Store` / `Reducer` / `Middleware` / reducer composition 在 `@MainActor`
2. 异步副作用通过 `runTask` 或 `Task` 脱离主 actor
3. 异步结果通过 `dispatch` 回到主 actor 状态流

也就是：

```text
UI
  -> dispatch(action)
  -> Middleware (@MainActor)
  -> Reducer (@MainActor)
  -> Store.state mutation (@MainActor)

Async side effect
  -> runTask / Task
  -> async work
  -> await dispatch(follow-up action)
  -> back to MainActor state flow
```

## 相比旧设计的收益

### 1. 编译器、公开 API、运行模型一致

旧设计更像是“运行时大体在主线程，但类型系统没有完全承认”。

新设计下：

1. Swift 6 编译器检查
2. 对外暴露的类型契约
3. 实际状态演进路径

三者都描述同一个 MainActor 模型。

### 2. 接入方不再承担并发补丁

接入方不需要再给模块级 reducer 常量手动补 `@MainActor`，库层直接承担这份契约。

### 3. 组合器不再是“半隔离”

如果只改 `Reducer` 而不改 `pullback` / `combineReducers`，Swift 6 仍会在组合阶段报隔离捕获问题。现在这条链路已经闭合。

## 验证结果

本轮收口完成后：

1. `swift build` 通过
2. `swift test` 通过
3. Swift 6 严格并发最小复现已验证通过

## 一句话总结

> TGReduxKit 现在是一套以 MainActor 作为状态演进边界、面向 Swift 6+ 严格并发环境的状态管理库。

接入方若使用 Xcode 26 的「默认 MainActor」App 模板，领域 State / Action 应放在无 MainActor 默认的 Domain 模块（见 Demo 的 `ShoppingDomain`），而不是在 App 里逐类型标 `nonisolated`。详见 [DEFAULT_ACTOR_ISOLATION_AND_REDUX.md](./DEFAULT_ACTOR_ISOLATION_AND_REDUX.md)。
