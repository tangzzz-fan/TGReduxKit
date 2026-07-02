# 模块化 Reducer（组合式）

使用 `combineReducers` 和 `pullback` 将 Feature reducer 组合为根 reducer：

```swift
struct AppState {
    var counter: CounterState
    var user: UserState
}

let appReducer: Reducer<AppState, AppAction> = combineReducers(
    pullback(counterReducer,
        state: \.counter,
        extract: { if case .counter(let a) = $0 { a } else { nil } }
    ),
    pullback(userReducer,
        state: \.user,
        extract: { if case .user(let a) = $0 { a } else { nil } }
    )
)
```

`pullback` 将子 reducer 从 `(ChildState, ChildAction)` 提升为 `(ParentState, ParentAction)`，只在 extract 返回非 nil 时运行。`combineReducers` 按声明顺序执行所有子 reducer。**每个 Feature 一条线，新增模块只加一行。**

注：也可以继续使用手写 switch 的方式——两种写法完全等价。组合式在 Feature 数量 ≥3 时更清晰。

## 为什么需要 pullback：子 Reducer 的边界

`pullback` 不是简单的语法糖——它强制了**关注点分离**。以下场景来自 Demo 的 `Redux.swift`（见 `../Examples/TGReduxKitDemo`）。

**子 Reducer 能做的事（独立模块，纯状态变换）：**

```swift
// catalogReducer 只操作 CatalogState——不接触 CartState 或 FeatureFlagsState
let catalogReducer: Reducer<CatalogState, CatalogAction> = { state, action in
    switch action {
    case .searchQueryChanged(let query):
        state.searchQuery = query            // ✅ 操作自己的字段
        state.isSearching = !query.isEmpty   // ✅
    case .searchCompleted:
        state.isSearching = false            // ✅
    }
}
```

**子 Reducer 做不到的事（需要父级介入）：**

> 子 Reducer 的 State 类型是 `CatalogState`，它**看不到**父级的 `FeatureFlagsState.snapshot`。因此 Feature Flag 刷新后，子 Reducer 无法更新 `CatalogState.showsFreeShippingBanner` 这类派生展示字段。

这些逻辑应该放在一个**父级 cross-cutting reducer** 中：

```swift
// crossCuttingReducer：处理子 Reducer 边界之外的三类事情
let crossCuttingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .featureFlags(.loaded(let snapshot, _)):
        // 1️⃣ Flag → 派生展示字段映射（子 Reducer 不持有 snapshot）
        state.catalog.showsFreeShippingBanner = snapshot.showsFreeShippingBanner
        state.catalog.showsRecommendedBadge = snapshot.showsRecommendedBadge
        state.isExpressCheckoutAvailable = snapshot.isExpressCheckoutEnabled   // 顶层字段

    case .navigation(let navAction):
        // 2️⃣ 路由（直接操作根 State 的 navigation 字段）
        navigationReducer(state: &state.navigation, action: navAction)

    case .handleDeepLink(let url):
        // 3️⃣ Deep Link（需要跨多个子 State 查找/组装数据）
        if let product = state.product(for: productID) { ... }
    }
}

// 组装
let shoppingReducer = combineReducers(
    pullback(catalogReducer, ...),
    pullback(cartReducer, ...),
    pullback(featureFlagsReducer, ...),
    crossCuttingReducer    // ← 处理子 Reducer 边界之外的事
)
```

**三种职责的分工：**

| | 子 Reducer（pullback 包装） | 父级 cross-cutting reducer |
|---|---|---|
| 操作对象 | 只操作自己的 ChildState | 可读写任意子状态 + 根级字段 |
| 适合处理 | 单 Feature 内的纯状态变换 | 多 Feature 联动、路由、派生映射 |
| 编译期约束 | extract 返回 nil 时不执行 | 所有 Action 都会收到 |
| 新增模块 | 加一行 `pullback(...)` | 不改 crossCuttingReducer |

完整的 Demo 代码见 `../Examples/TGReduxKitDemo/TGReduxKitDemo/Redux.swift`。

> 更多实战场景（购物 App + 车载 App）见 [多 Feature 联动指南](MULTI_FEATURE_GUIDE.md)。
