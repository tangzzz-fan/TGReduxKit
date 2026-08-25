# 依赖注入（无 DI 容器）

> **5.0 现行**：每个 Middleware **工厂函数**在构造时接收自己的依赖；Composition Root 直接组装。  
> **不要**再建 `*Dependencies` 协议袋（那是 4.x 把一堆服务塞进一个 struct 再往下传的习惯）。

TGReduxKit **不引入** `DependencyValues` / `@Dependency`。只用 Swift **闭包捕获** + **工厂参数** + **Composition Root**。

## 分层规则

| 层级 | 依赖 | 方式 |
|------|------|------|
| **Reducer** | 不允许 | 纯 `(inout State, Action) -> Void` |
| **Middleware** | 允许且必须 | `makeFooMiddleware(api:)` 参数注入，闭包捕获 |
| **Effect 闭包** | 允许 | 捕获 Sendable 依赖 |
| **Store** | 无业务依赖 | 只持有 state / reducer / middlewares 数组 |

## Demo：Composition Root 直接接线

```text
ShoppingAppView(productSearch:…, featureFlags:…, now:…)   ← Composition Root
        │
        ├─ makeCatalogSearchMiddleware(productSearch:)
        ├─ makeFeatureFlagsMiddleware(featureFlags:now:)
        └─ makeAsyncLabMiddleware()
                │
                ▼  各工厂返回的 Middleware 已捕获依赖 → Store(middlewares:)
```

```swift
// App / Preview — 5.0
ShoppingAppView()  // live defaults

ShoppingAppView(
  productSearch: MockSearch(),
  featureFlags: PreviewFeatureFlagService(),
  now: { fixedDate }
)

// 工厂本身（Shopping 模块）
func makeCatalogSearchMiddleware(productSearch: any ProductSearching) -> Middleware<…> { … }
func makeFeatureFlagsMiddleware(featureFlags: any FeatureFlagFetching, now: …) -> Middleware<…> { … }
```

- 协议与 live 实现：`Services.swift`（`ProductSearching` / `FeatureFlagFetching`）
- 测试：对**单个**工厂传入 mock，不必构造依赖袋

## Reducer 需要时间 / UUID 时

不要在 Reducer 里调 `Date()` / `UUID()`。由 Middleware（或 View）写入 Action：

```swift
.task {
  .loaded(snapshot, now())  // now 由工厂参数捕获
}
```

## 相对 TCA `@Dependency`

| | 本方案 | TCA Dependency |
|--|--------|----------------|
| 解析时机 | 编译期（工厂参数） | 运行时键查找 |
| 全局状态 | 无 | `DependencyValues` |
| 测试 | 换工厂实参 | 改全局注册表 |
| 聚合袋 | **不需要** | — |

**原则**：依赖在架构门口（**每个** Middleware 工厂）注入，不渗入 Reducer，不塞进 Store，也不先装进一个 `*Dependencies` 再二次分发。
