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

let fixedNow = Date(timeIntervalSince1970: 0)

let store = Store(
    initialState: ShoppingState(),
    reducer: shoppingReducer,
    middlewares: [
        makeCatalogSearchMiddleware(productSearch: MockSearch()),
        makeFeatureFlagsMiddleware(
            featureFlags: LiveFeatureFlagService(),
            now: { fixedNow }          // 注入固定时间 → 断言可复现
        ),
        makeAsyncLabMiddleware()
    ]
)
store.dispatch(.catalog(.searchQueryChanged("pad")))
// 短暂等待 Effect 完成后再断言 state
```

> `now` / `uuid` **没有默认值**。这是刻意的：默认参数是隐式依赖，省略仍能编译，
> `Date()` 会悄悄进入业务路径，测试也就失去可复现性。

## 用 DI 容器时的隔离

若被测代码走 Factory，**优先换实参**而不是改容器。确实需要改容器时，用 `@TaskLocal` 隔离：

```swift
Container.$shared.withValue(Container()) {
    Container.shared.featureFlags.register { MockFeatureFlagService() }
    // 断言都在这个作用域内；退出后容器恢复
}
```

裸 `register` 是**永久替换**，并行测试之间会互相污染。

## 第三层：Effect 结构抽检（~5%）

直接调用 middleware，断言 `Effect.operation` 为 `.task` / `.merge` / `.debounce` / `.cancel`，不必跑 IO。库内示例见 `Tests/TGReduxKitTests/AuditedArchitectureTests.swift`。

## 不要测什么

- Reducer 内不要出现真实网络 / `Date()` / `UUID()`  
- 不要依赖全局 DI 注册表覆盖  
