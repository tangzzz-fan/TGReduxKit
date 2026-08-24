# 测试指南

使用 TGReduxKit 时，业务代码有三层可测试的粒度，推荐按 **80 / 15 / 5** 的比例分配：

## 第一层：纯 Reducer 测试（主力，~80%）

用 `TestStore` 同步测试状态机逻辑——不需要 App、不需要 middleware、不需要异步等待。

```swift
import Testing
@testable import YourApp

@Test func searchFlow() throws {
    let store = TestStore(initialState: CatalogState(), reducer: catalogReducer)

    // 用户输入 → 进入搜索态
    store.send(.searchQueryChanged("iPhone"))
    #expect(store.state.isSearching == true)

    // 结果返回 → 退出搜索态
    store.send(.searchCompleted("iPhone", [iphoneProduct]))
    #expect(store.state.isSearching == false)
    #expect(store.state.visibleProducts.count == 1)

    // 清空 → 重置
    store.send(.searchQueryChanged(""))
    try store.assert("clearing query should exit searching mode") { state in
        state.isSearching == false && state.visibleProducts.isEmpty == false
    }
}
```

这一层覆盖了所有状态转移路径——bug 最常见的地方。

`TestStore` 的 `send(_:expect:)` / `assert(...)` 现在通过抛出 `TestStoreAssertionError` 报告失败，因此可以直接和 Swift Testing、XCTest 的错误模型对齐，而不会用 `fatalError` 终止整个测试进程。

## 第二层：Middleware 单元测试（补充，~15%）

Middleware 是闭包，可以构造 Store + mock 依赖来直接测试，不需要启动 App：

```swift
@Test func searchDebounceCancelsPreviousTask() async throws {
    let mockService = MockSearchService()
    let deps = ShoppingDependencies(productSearchService: mockService)

    let store = Store(
        initialState: ShoppingState(),
        reducer: shoppingReducer,
        middlewares: [makeProductSearchMiddleware(dependencies: deps)]
    )

    // 快速连续输入 3 次
    store.dispatch(.catalog(.searchQueryChanged("i")))
    store.dispatch(.catalog(.searchQueryChanged("ip")))
    store.dispatch(.catalog(.searchQueryChanged("iph")))

    // 防抖期间，搜索尚未触发
    #expect(mockService.callCount == 0)

    // 等待 debounce（300ms）
    try await Task.sleep(nanoseconds: 400_000_000)

    // 只触发一次，且使用最终 query
    #expect(mockService.callCount == 1)
    #expect(mockService.lastQuery == "iph")
}
```

关键技巧：把网络、数据库等外部依赖**协议化**，在测试中注入 mock。这与 Demo 中 `ShoppingDependencies` 的设计一致。

## 第三层：集成冒烟测试（少量，~5%）

把 middleware + reducer 串联，验证关键业务流程的端到端状态流转：

```swift
@Test func fullSearchAndAddToCart() async throws {
    let store = Store(
        initialState: ShoppingState(),
        reducer: shoppingReducer,
        middlewares: [makeProductSearchMiddleware(dependencies: .test)]
    )

    store.dispatch(.catalog(.searchQueryChanged("MacBook")))
    try await Task.sleep(nanoseconds: 400_000_000)

    // 搜索结果正确
    #expect(store.state.catalog.visibleProducts.count == 1)

    // 加入购物车后的状态
    store.dispatch(.cart(.add(store.state.catalog.visibleProducts[0])))
    #expect(store.state.cart.totalQuantity == 1)
    #expect(store.state.cart.totalPrice == 1999)
}
```

## 速度对比

| 层级 | 单次耗时 | 依赖 | 适合测什么 |
|------|---------|------|-----------|
| TestStore（纯 reducer） | 微秒级 | 无 | 状态机逻辑 |
| Middleware 单测 | 毫秒级 | Mock 协议 | 副作用编排（debounce、重试） |
| 集成测试 | 百毫秒级 | Mock + sleep | 关键流程冒烟 |
