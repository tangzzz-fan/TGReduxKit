# 模块化 Reducer（组合式）

> **5.0**：`Reducer` 始终为纯 `(inout State, Action) -> Void`。组合只影响状态树切分，副作用仍在 Middleware。

使用 `combineReducers` 和 `pullback` 将 Feature reducer 组合为根 reducer：

```swift
let appReducer: Reducer<AppState, AppAction> = combineReducers(
    pullback(
        counterReducer,
        state: \.counter,
        action: AppAction.counter,
        extract: { if case .counter(let a) = $0 { a } else { nil } }
    ),
    pullback(
        userReducer,
        state: \.user,
        action: AppAction.user,
        extract: { if case .user(let a) = $0 { a } else { nil } }
    )
)
```

`pullback` 将子 reducer 从 `(ChildState, ChildAction)` 提升为 `(ParentState, ParentAction)`，只在 `extract` 返回非 nil 时运行。`combineReducers` 按声明顺序执行。**每个 Feature 一条线，新增模块只加一行。**

## 子 Reducer 边界与 cross-cutting

场景来自 Demo：`Examples/TGReduxKitDemo/Shopping/Sources/Shopping/Redux.swift`。

**子 Reducer** 只操作自己的 `ChildState`（如 `CatalogState`），看不到兄弟 Feature 的 Flag snapshot。

**父级 cross-cutting reducer** 处理：

1. Flag → 派生展示字段  
2. 导航 / Deep Link  
3. 需要同时读多个子树的同步派生  

```swift
let shoppingReducer = combineReducers(
    pullback(catalogReducer, state: \.catalog, action: ShoppingAction.catalog, extract: …),
    pullback(cartReducer, state: \.cart, action: ShoppingAction.cart, extract: …),
    pullback(featureFlagsReducer, state: \.featureFlags, action: ShoppingAction.featureFlags, extract: …),
    crossCuttingReducer
)
```

| | 子 Reducer（pullback） | 父级 cross-cutting |
|--|------------------------|-------------------|
| 操作对象 | 仅 ChildState | 任意子状态 + 根字段 |
| 适合 | 单 Feature 纯变换 | 多 Feature 联动、路由、派生 |
| IO | 禁止 | 禁止（IO 走 Middleware） |

异步搜索 / 拉 Flag：见同文件中的 `makeCatalogSearchMiddleware` / `makeFeatureFlagsMiddleware`。
