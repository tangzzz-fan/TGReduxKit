# TGReduxKit

轻量 Redux for SwiftUI（iOS 17+）— **5.0**

**纯 Reducer（`Void`）+ Middleware → `Effect` + `@MainActor @Observable` `Store`**

领域 `State` / `Action` / `Reducer` 保持非隔离纯函数；副作用与依赖只在 Middleware 边界注入（无 DI 容器）。

## 架构

```mermaid
flowchart LR
  View --> Store
  Store --> Middleware
  Middleware -->|Effect| Store
  Middleware -->|next| Reducer
  Reducer -->|inout State| Store
  Effect -->|follow-up Action| Store
```

| Product | 职责 |
|---------|------|
| `TGReduxKitCore` | `State` / `Action` / 纯 `Reducer` / `Effect` / `CancellationID` |
| `TGReduxKitRuntime` | `@MainActor` `Store`、Middleware→Effect、`ScopedStore` |
| `TGReduxKitUI` | `provideStore` / `binding` |
| `TGReduxKitDebug` | logging / state-diff / error-reporting |
| `TGReduxKitTesting` | `TestStore`（纯 Reducer） |
| `TGReduxKit` | Umbrella（Core+Runtime+UI+Debug） |

- 架构：[ARCHITECTURE.md](ARCHITECTURE.md) · [Docs/ADR_AUDITED_MIDDLEWARE_EFFECT.md](Docs/ADR_AUDITED_MIDDLEWARE_EFFECT.md)
- DI：[Docs/DEPENDENCY_INJECTION.md](Docs/DEPENDENCY_INJECTION.md)

## 快速开始

```swift
import TGReduxKit

struct AppState: Equatable, Sendable, State { var count = 0 }
enum AppAction: Sendable, Action { case increment, load, loaded(Int) }

let reducer: Reducer<AppState, AppAction> = { state, action in
    switch action {
    case .increment: state.count += 1
    case .loaded(let value): state.count = value
    case .load: break
    }
}

func makeLoadMiddleware(fetch: @escaping @Sendable () async -> Int) -> Middleware<AppState, AppAction> {
    { _, action, next in
        let base = next(action)
        guard case .load = action else { return base }
        return .merge(base, .task { .loaded(await fetch()) })
    }
}

// Composition Root
@SwiftUI.State var store = Store(
    initialState: AppState(),
    reducer: reducer,
    middlewares: [makeLoadMiddleware(fetch: { 42 })]
)
```

## 取消与竞态（重要）

`CancellationID` **只保证** Store 取消对应 `Task`（同 id 替换 = latest-wins）。Swift 的取消是**协作式**的：

1. **必须在长循环 / 每次 `await` 之后再查** `Task.isCancelled`，否则 Effect 还会继续跑，甚至通过中间的 `store.dispatch` 脏写状态（Store 只拦 Effect **返回值**上的 follow-up，不拦你手动 `dispatch`）。
2. **就算循环里查了 `Task.isCancelled`，仍可能出竞态**：检查与下一次 `await` 之间有窗口；网络已返回、cancel 才到达时，若不在 `await` 后再 guard，仍可能交出过期结果。Reducer 侧要用请求令牌 / `query == state.searchQuery` 再挡一层（Demo 搜索即如此）。
3. 因此正确心智是三层，而不是「标了 id 就安全」：

| 层 | 做什么 |
|----|--------|
| `CancellationID` | 取消 / 替换 Task |
| `Task.isCancelled` | 协作停手，避免 cancel 后继续 `dispatch` |
| Reducer guard | 逻辑 latest-wins，堵住检查窗口里溜进来的过期 Action |

论述出处：[Docs/WHY_REDUX_ADOPTION.md](Docs/WHY_REDUX_ADOPTION.md) §风险、[Docs/EFFECT_GUIDE.md](Docs/EFFECT_GUIDE.md)。Demo **Async Lab** 可开关「Respect Task.isCancelled」对比干净取消 vs 脏写泄漏。

## 安装

```swift
.package(url: "https://github.com/tangzzz-fan/TGReduxKit", from: "5.0.0"),
```

```swift
.product(name: "TGReduxKit", package: "TGReduxKit")
```

## 文档

| 文档 | 说明 |
|------|------|
| [Docs/README.md](Docs/README.md) | 索引（仅现行 5.0） |
| [Docs/MIGRATION_4_TO_5.md](Docs/MIGRATION_4_TO_5.md) | 4.x → 5.0 |
| [Docs/EFFECT_GUIDE.md](Docs/EFFECT_GUIDE.md) | Effect / 取消 / 竞态 |
| [CHANGELOG.md](CHANGELOG.md) | 版本记录 |

## 要求

- Swift 6.0+
- iOS 17 / macOS 14 / tvOS 17 / watchOS 10

## License

MIT
