# Docs Index

> **现行文档集（5.0.0）**。已删除的三角架构 / industrial / DependencyContext / 时间旅行等文稿请勿再引用；历史版本说明仅留在 `CHANGELOG.md`。

TGReduxKit **5.0**：纯 `Reducer` → `Void`；Middleware 返回 `Effect`；`@MainActor @Observable` `Store`。

## 必读

| 文档 | 说明 |
|------|------|
| [ADR_AUDITED_MIDDLEWARE_EFFECT.md](./ADR_AUDITED_MIDDLEWARE_EFFECT.md) | 架构决策 |
| [DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md) | 闭包 / 工厂注入（无 DI 容器） |
| [MIGRATION_4_TO_5.md](./MIGRATION_4_TO_5.md) | 4.x → 5.0 |
| [EFFECT_GUIDE.md](./EFFECT_GUIDE.md) | Effect、取消、debounce、竞态 |
| [TESTING_GUIDE.md](./TESTING_GUIDE.md) | Reducer / Middleware / Store 测试 |

## 实践

| 文档 | 说明 |
|------|------|
| [REDUCER_COMPOSITION.md](./REDUCER_COMPOSITION.md) | `combineReducers` / `pullback` |
| [ERROR_HANDLING.md](./ERROR_HANDLING.md) | 错误 Action + reporting middleware |
| [CROSS_FEATURE_COMMUNICATION.md](./CROSS_FEATURE_COMMUNICATION.md) | 跨 Feature 协调 |
| [DEFAULT_ACTOR_ISOLATION_AND_REDUX.md](./DEFAULT_ACTOR_ISOLATION_AND_REDUX.md) | MainActor 默认隔离与领域模块 |
| [STRICT_CONCURRENCY_MIGRATION.md](./STRICT_CONCURRENCY_MIGRATION.md) | Swift 6 并发边界 |
| [WHY_REDUX_ADOPTION.md](./WHY_REDUX_ADOPTION.md) | 为何采用轻量 Redux |

Demo 对照：`Examples/TGReduxKitDemo`（`ShoppingDependencies` + middleware 工厂）。
