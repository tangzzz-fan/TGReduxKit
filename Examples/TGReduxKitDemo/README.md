# TGReduxKitDemo

> 对照 **TGReduxKit 5.0**：纯 Reducer + Middleware→Effect + 工厂 DI。

| Piece | Role |
|-------|------|
| `Shopping` SPM | Models、纯 Reducer、Middleware 工厂、服务协议 — 无 MainActor 默认 |
| App | Composition Root：组装 `ShoppingDependencies` → `Store` |

## 异步流（已内置）

| Demo | 机制 |
|------|------|
| 搜索 | `Effect.debounce` + 清空时 `.cancel` + `await` 后 `Task.isCancelled` + Reducer `query` guard |
| Feature Flags | `Effect.task`；可开关「Simulate next load failure」→ `.loadFailed` |
| **Async Lab** | 长任务 + Cancel；开关 **Respect Task.isCancelled** — 关掉则演示 cancel 后仍 `dispatch` 的泄漏 |

要点：标了 `CancellationID` ≠ 无竞态；循环里查 `isCancelled` 仍可能有窗口竞态，需 Reducer 再挡。见仓库 README「取消与竞态」。

## 依赖注入（无 DI 框架）

```swift
ShoppingAppView(dependencies: .live)
// Preview / test: ShoppingDependencies(productSearch: Mock…, featureFlags: …)
```

## Run

打开 `TGReduxKitDemo.xcodeproj`，本地包：`Shopping`、`TGReduxKit`、`TGNavigationStack`。
