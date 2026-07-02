# 跨 Feature 通信

当 Feature A（如购物车）的变化需要触发 Feature B（如推荐）的副作用时，有几种模式可选。

## 模式一：父级 Middleware 转发（推荐）

在根 Store 的 middleware 数组中放置一个"协调 middleware"，监听跨 Feature 事件：

```swift
let crossFeatureMiddleware: Middleware<ShoppingState, ShoppingAction> = { store, action, next in
    next(action)

    // Feature A 的事件 → 触发 Feature B 的副作用
    if case .cart(.add(let product)) = action {
        store.runTask(id: "refresh-recommendations") {
            let recommendations = await recService.recommendations(basedOn: product)
            await store.dispatch(.recommendations(.updated(recommendations)))
        }
    }
}

let store = Store(
    initialState: ShoppingState(),
    reducer: shoppingReducer,
    middlewares: [
        // 先注册 Feature 专用 middleware
        makeProductSearchMiddleware(dependencies: deps),
        cartMiddleware,
        // 最后注册跨 Feature 协调 middleware
        crossFeatureMiddleware,
    ]
)
```

**适用场景**：Feature A 触发 Feature B 的副作用（如加购后刷新推荐）。

## 模式二：Reducer 内联联动

如果 Feature B 只需要**同步**更新派生状态，直接在 reducer 中处理——不需要 middleware：

```swift
let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .cart(.add(let product)):
        // Feature A 自己的状态更新
        if let index = state.cart.items.firstIndex(where: { $0.product.id == product.id }) {
            state.cart.items[index].quantity += 1
        } else {
            state.cart.items.append(CartItem(product: product))
        }
        // Feature B 的派生状态同步更新
        state.recommendations.lastAddedProductID = product.id

    // ...其他 case
    }
}
```

**适用场景**：Feature B 只需要同步读取 Feature A 的状态变化结果。

## 模式三：Action 嵌套（编译期约束）

通过 `ScopedStore` 的 action 映射，子 Feature 天然只能发自己的 action，无法"不小心"影响兄弟 Feature。如果确需跨 Feature，必须在父级定义显式的转发 action：

```swift
enum ShoppingAction: Equatable {
    case catalog(CatalogAction)
    case cart(CartAction)
    case recommendations(RecommendationsAction)
    // 显式的跨 Feature 协调 action
    case cartDidUpdate(lastAddedProduct: Product)
}
```

**适用场景**：需要编译期强约束，所有跨 Feature 行为都在父级显式声明。

## 推荐组合

| 场景 | 推荐模式 |
|------|---------|
| A 事件 → B 异步副作用 | 模式一（父级 middleware） |
| A 状态变化 → B 同步派生 | 模式二（reducer 内联） |
| 大型团队、需编译期约束 | 模式三（显式协调 action） |
