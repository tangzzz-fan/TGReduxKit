# TGReduxKitDemo

> 对照 **TGReduxKit 5.0**：纯 Reducer + Middleware→Effect；DI = **工厂参数**（无 `*Dependencies` 袋）。

| Piece | Role |
|-------|------|
| `Shopping` SPM | Models、纯 Reducer、服务协议 / live、各 Middleware 工厂 |
| App | Composition Root：`makeXMiddleware(deps…)` → `Store` |

## 依赖注入（5.0）

```swift
// Composition Root — 直接传给工厂，不要 ShoppingDependencies 袋
ShoppingAppView(
  productSearch: LiveProductSearchService(),
  featureFlags: LiveFeatureFlagService(),
  now: { Date() }
)

// Preview / test
ShoppingAppView(featureFlags: PreviewFeatureFlagService())
```

## 异步流

| Demo | 机制 |
|------|------|
| 搜索 | `Effect.debounce` + 清空 `.cancel` + `await` 后 `isCancelled` + Reducer query guard |
| Feature Flags | `Effect.task`；可模拟 `.loadFailed` |
| Async Lab | 长任务 + Cancel；开关 Respect `Task.isCancelled` 对比泄漏 |

见仓库 README「取消与竞态」。

## Run

打开 `TGReduxKitDemo.xcodeproj`，本地包：`Shopping`、`TGReduxKit`、`TGNavigationStack`。
