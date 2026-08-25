# 测试指南

> **5.0**：测纯 Reducer 为主；异步用 mock 注入 Middleware 工厂。无 `DependencyValues`。

推荐 **80 / 15 / 5**：纯 Reducer → Middleware（mock）→ 少量 Store 集成。

## 第一层：纯 Reducer（~80%）

```swift
import Testing
import TGReduxKit

@Test func searchFlow() throws {
    let store = TestStore(initialState: CatalogState(), reducer: catalogReducer)

    store.send(.searchQueryChanged("iPhone"))
    #expect(store.state.isSearching == true)

    store.send(.searchCompleted("iPhone", [iphoneProduct]))
    #expect(store.state.isSearching == false)

    try store.assert { !$0.isSearching }
}
```

`TestStore` 失败抛 `TestStoreAssertionError`（兼容 Swift Testing）。

也可直接调用 `catalogReducer(&state, action)`，无需 `TestStore`。

## 第二层：工厂注入 mock（~15%）

```swift
struct MockSearch: ProductSearching {
    func searchProducts(query: String, in products: [Product]) async -> [Product] {
        products.filter { $0.name.contains(query) }
    }
}

let middlewares = makeShoppingMiddlewares(
    dependencies: ShoppingDependencies(productSearch: MockSearch())
)
let store = Store(
    initialState: ShoppingState(),
    reducer: shoppingReducer,
    middlewares: middlewares
)
store.dispatch(.catalog(.searchQueryChanged("pad")))
// 短暂等待 Effect 完成后再断言 state
```

## 第三层：Effect 结构抽检（~5%）

直接调用 middleware，断言 `Effect.operation` 为 `.task` / `.merge` / `.debounce` / `.cancel`，不必跑 IO。库内示例见 `Tests/TGReduxKitTests/AuditedArchitectureTests.swift`。

## 不要测什么

- Reducer 内不要出现真实网络 / `Date()` / `UUID()`  
- 不要依赖全局 DI 注册表覆盖  
