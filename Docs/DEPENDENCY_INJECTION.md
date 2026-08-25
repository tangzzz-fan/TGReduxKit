# 依赖注入（无框架必选；可选对接 Factory）

> **5.0 现行**：每个 Middleware **工厂函数**在构造时接收自己的依赖；Composition Root 组装。  
> TGReduxKit **不内置** DI 容器。可用纯参数接线，也可用 [Factory](https://github.com/hmlongco/Factory) 等框架**只在门口解析**。

## 分层规则

| 层级 | 依赖 | 方式 |
|------|------|------|
| **Reducer** | 不允许 | 纯 `(inout State, Action) -> Void` |
| **Middleware** | 允许且必须 | `makeFooMiddleware(api:)` 参数注入，闭包捕获 |
| **Effect 闭包** | 允许 | 捕获 Sendable 依赖 |
| **Store** | 无业务依赖 | 只持有 state / reducer / middlewares |
| **DI 框架** | 仅 Composition Root | 解析服务 → 传入 Middleware 工厂；**不要** `@Injected` 进 Reducer |

## A) 无 Factory（Demo：`ManualDIShoppingAppView`）

```text
ManualDIShoppingAppView(productSearch:…, featureFlags:…)
        │
        ▼
ShoppingStoreBootstrap.makeStore(…)
        ├─ makeCatalogSearchMiddleware(productSearch:)
        ├─ makeFeatureFlagsMiddleware(featureFlags:now:)
        └─ makeAsyncLabMiddleware()
```

```swift
ManualDIShoppingAppView()
ManualDIShoppingAppView(featureFlags: PreviewFeatureFlagService())
```

适合：示例、小应用、测试时直接塞 mock。

## B) 使用 Factory / FactoryKit（Demo：`FactoryDIShoppingAppView`）

在 **App 层**注册（`Container+Shopping.swift`），Shopping 模块仍不依赖 Factory：

```swift
import FactoryKit
import Shopping

extension Container {
    var productSearch: Factory<any ProductSearching> {
        self { LiveProductSearchService() }
    }
    var featureFlags: Factory<any FeatureFlagFetching> {
        self { LiveFeatureFlagService() }
    }
    var now: Factory<@Sendable () -> Date> {
        self { { Date() } }
    }
}
```

Composition Root **解析后再交给同一套** Middleware 工厂：

```swift
FactoryDIShoppingAppView()  // Container.shared.productSearch() 等

// Preview / test override
Container.shared.featureFlags.register { PreviewFeatureFlagService() }
FactoryDIShoppingAppView()
```

```text
Container.shared ──resolve──► productSearch / featureFlags / now
        │
        ▼ 仍调用 ShoppingStoreBootstrap.makeStore(…)
        │
        ▼ 与 A 完全相同的 make*Middleware + Store
```

| 做法 | OK? |
|------|-----|
| Root 里 `container.api()` 再 `makeAPIMiddleware(api:)` | ✅ |
| Middleware 工厂参数捕获服务 | ✅ |
| `@Injected` / `Container` 写进 Reducer | ❌ |
| `Store` 持有 `Container` | ❌ |

## Demo 入口

运行 App → **Composition Root** 列表可选 Manual / FactoryKit。两套 UI 与异步 Demo 相同。

## Reducer 需要时间 / UUID

由 Middleware 工厂参数注入的 `now` / `uuid` 写入 Action，不要在 Reducer 里直接 `Date()`。

## 相对 TCA `@Dependency`

| | 本方案 | TCA Dependency |
|--|--------|----------------|
| 解析时机 | 工厂参数（+ 可选 Factory 在 Root） | 运行时键查找 |
| 全局状态 | 可选（仅 Factory Container） | `DependencyValues` |
| 测试 | 换工厂实参或 `Factory.register` | 改全局注册表 |

**原则**：无论有没有 Factory，依赖都停在架构门口；Reducer / Store 保持干净。
