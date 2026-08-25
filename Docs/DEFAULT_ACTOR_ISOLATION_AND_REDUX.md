# Default Actor Isolation（5.0）

Xcode / 部分 App target 可能默认 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`。领域模型若与 UI 同 target，会被迫到处标 `nonisolated`。

## 推荐边界

| 层 | 隔离 | 内容 |
|----|------|------|
| SPM Domain（如 Demo `Shopping`） | **无** MainActor 默认 | `State` / `Action` / 纯 Reducer / 服务协议 |
| `TGReduxKitRuntime` | `@MainActor` `Store` | 调度、`managedTasks` |
| App / Views | 可默认 MainActor | View、Composition Root 组装 Store |

不要在领域类型上喷 `nonisolated` 补丁；把领域代码放进独立 SPM target。

业务依赖用 Middleware 工厂注入（[DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md)），不要塞进 Store。
