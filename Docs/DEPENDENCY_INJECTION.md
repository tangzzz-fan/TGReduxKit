# 依赖注入（无 DI 容器）

TGReduxKit **不引入** `DependencyValues` / `@Dependency` 一类运行时注册表。依赖管理仍是架构必要部分，但只用 Swift **闭包捕获** + **工厂函数** + **Composition Root 组装**。

## 分层规则

| 层级 | 依赖 | 方式 |
|------|------|------|
| **Reducer** | 不允许 | 纯 `(inout State, Action) -> Void` |
| **Middleware** | 允许且必须 | 工厂参数注入，闭包捕获 |
| **Effect 闭包** | 允许 | 捕获 Sendable 依赖 |
| **Store** | 无业务依赖 | 只持有 state / reducer / middlewares |

## Demo：Shopping

```text
ShoppingAppView(dependencies:)          ← Composition Root
        │
        ▼
ShoppingDependencies { productSearch, featureFlags, now }
        │
        ▼
makeShoppingMiddlewares(dependencies:)  ← 工厂把门
        │
        ├─ makeCatalogSearchMiddleware(productSearch:)
        └─ makeFeatureFlagsMiddleware(featureFlags:now:)
                │
                ▼  Effect.task / .debounce 闭包内使用依赖
```

- 协议：`ProductSearching` / `FeatureFlagFetching`
- 生产：`LiveProductSearchService` / `LiveFeatureFlagService`
- 预览：`ShoppingAppView(dependencies: ShoppingDependencies(featureFlags: Preview…))`
- 测试：传入 mock，断言 Middleware 返回的 `Effect` 结构，或跑 Store 等待 follow-up

## Reducer 需要时间 / UUID 时

不要在 Reducer 里调 `Date()` / `UUID()`。由 Middleware（或 View）写入 Action：

```swift
// Middleware
store.dispatch(.createTodo(uuid(), now()))
return .none()

// Reducer
case .createTodo(let id, let date):
    state.todos.append(Todo(id: id, createdAt: date))
```

Demo 中 feature flags 完成时间即由 `now` 闭包注入，经 `.loaded(snapshot, now())` Action 进入纯 Reducer。

## 相对 TCA `@Dependency`

| | 本方案 | TCA Dependency |
|--|--------|----------------|
| 解析时机 | 编译期（工厂参数） | 运行时键查找 |
| 全局状态 | 无 | `DependencyValues` |
| 测试 | 换 mock 工厂实参 | 改全局注册表 |
| 宏 | 无 | 需要 |

**原则**：依赖在架构门口（Middleware 工厂）注入，不渗入 Reducer，也不塞进 Store。
