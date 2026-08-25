# TGReduxKitDemo

> **TGReduxKit 5.0**：纯 Reducer + Middleware→Effect。DI 演示 **两套 Composition Root**。

## Composition Root（启动后可选）

| 入口 | 说明 |
|------|------|
| **Manual (no Factory)** | `ManualDIShoppingAppView` — 构造参数直接传入服务 |
| **FactoryKit** | `FactoryDIShoppingAppView` — `Container` 解析后再交给同一套 `make*Middleware` |

两者共用 `ShoppingStoreBootstrap.makeStore`；Shopping SPM **不依赖** Factory。

```swift
// A) Manual
ManualDIShoppingAppView(featureFlags: PreviewFeatureFlagService())

// B) Factory — 注册见 DI/Container+Shopping.swift
Container.shared.featureFlags.register { PreviewFeatureFlagService() }
FactoryDIShoppingAppView()
```

详见仓库 `Docs/DEPENDENCY_INJECTION.md`。

## 异步流

| Demo | 机制 |
|------|------|
| 搜索 | `debounce` + 清空 `.cancel` + `isCancelled` + query guard |
| Feature Flags | `task`；可模拟失败 |
| Async Lab | 长任务 Cancel；Respect `Task.isCancelled` 对比泄漏 |

## Run

打开 `TGReduxKitDemo.xcodeproj`（已加 SPM：`Factory` → product **FactoryKit**）。
