# Docs Index

本目录按「接入指南 / 架构分析 / 审阅与维护」分层组织。

## 5.0 必读

| 文档 | 说明 |
|------|------|
| [DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md) | 闭包/工厂注入（无 DI 容器）；Demo 对照 |
| [ADR_AUDITED_MIDDLEWARE_EFFECT.md](./ADR_AUDITED_MIDDLEWARE_EFFECT.md) | **现行** 纯 Reducer + Middleware→Effect |
| [ADR_INDUSTRIAL_COMPROMISE.md](./ADR_INDUSTRIAL_COMPROMISE.md) | 先前 MainActor Store + Reducer→Effect 草案 |
| [MIGRATION_4_TO_5.md](./MIGRATION_4_TO_5.md) | 4.x → 5.0 迁移 |
| [EFFECT_GUIDE.md](./EFFECT_GUIDE.md) | Effect 创建、取消、debounce/throttle |
| [DEFAULT_ACTOR_ISOLATION_AND_REDUX.md](./DEFAULT_ACTOR_ISOLATION_AND_REDUX.md) | 为何不再需要领域 `nonisolated` |
| [STRICT_CONCURRENCY_MIGRATION.md](./STRICT_CONCURRENCY_MIGRATION.md) | Swift 6 并发模型（5.0） |
| [0825_REVIEW_UNION.md](./0825_REVIEW_UNION.md) | Review 并集映射 |

## 接入指南

| 文档 | 说明 |
|------|------|
| [ADVANCED_USAGE.md](./ADVANCED_USAGE.md) | 进阶用法（部分内容仍偏 4.x，迁移中） |
| [REDUCER_COMPOSITION.md](./REDUCER_COMPOSITION.md) | Reducer 组合 |
| [TESTING_GUIDE.md](./TESTING_GUIDE.md) | 测试 |
| [FEATURE_FLAG_GUIDE.md](./FEATURE_FLAG_GUIDE.md) | Feature Flag 示例思路 |

## 架构分析 / 审阅

| 文档 | 说明 |
|------|------|
| [ARCHITECTURE_COUNTEREXAMPLES.md](./ARCHITECTURE_COUNTEREXAMPLES.md) | 六组架构反例 vs 5.0 正向/负向验证 |
| [ARCHITECTURE_DI_AND_SHOPPING_MODULE.md](./ARCHITECTURE_DI_AND_SHOPPING_MODULE.md) | DependencyContext 统一注入 + Demo `Shopping` 模块：优点 / 缺点 / 否决方案 |
| [0825_reviews_01.md](./0825_reviews_01.md) / [0825_reviews_02.md](./0825_reviews_02.md) | 原始 review 文稿 |
| [ASYNC_RACE_AND_CANCELLATION.md](./ASYNC_RACE_AND_CANCELLATION.md) | 异步竞态（Effect 调度仍适用 latest-wins） |
| [WHY_REDUX_ADOPTION.md](./WHY_REDUX_ADOPTION.md) | 为何采用轻量 Redux |
| [REVIEW_REMEDIATION_REPORT.md](./REVIEW_REMEDIATION_REPORT.md) | 历史 remediation |
| [IMPLEMENTATION_SCORECARD.md](./IMPLEMENTATION_SCORECARD.md) | 评分卡（待按 5.0 刷新） |
