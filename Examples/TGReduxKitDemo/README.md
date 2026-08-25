# TGReduxKitDemo

| Piece | Role |
|-------|------|
| `Shopping` SPM | Models、纯 Reducer、Middleware 工厂、服务协议 — 无 MainActor 默认 |
| App | Composition Root：组装 `ShoppingDependencies` → `Store` |

## 依赖注入（无 DI 框架）

```swift
// Composition Root
ShoppingAppView(dependencies: .live)

// 或测试 / Preview
ShoppingAppView(
  dependencies: ShoppingDependencies(
    productSearch: MockSearch(),
    featureFlags: PreviewFeatureFlagService(),
    now: { fixedDate }
  )
)
```

Reducer **不**接收依赖；异步 IO 只在 `makeCatalogSearchMiddleware` / `makeFeatureFlagsMiddleware` 的闭包里使用捕获的服务。详见仓库 `Docs/DEPENDENCY_INJECTION.md`。

## Run

打开 `TGReduxKitDemo.xcodeproj`，本地包：`Shopping`、`TGReduxKit`、`TGNavigationStack`。
