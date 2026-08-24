# Docs Index

本目录按「接入指南 / 架构分析 / 审阅与维护」分层组织。先看接入指南，遇到边界或设计问题再进入分析文档。

## 接入指南

| 文档 | 说明 |
|------|------|
| [ADVANCED_USAGE.md](./ADVANCED_USAGE.md) | Scoped Store、root-only async、TestStore、调试中间件、时间旅行、DI 协作 |
| [REDUCER_COMPOSITION.md](./REDUCER_COMPOSITION.md) | `combineReducers` + `pullback` 组合式写法、子 Reducer 边界 |
| [CROSS_FEATURE_COMMUNICATION.md](./CROSS_FEATURE_COMMUNICATION.md) | 三种跨 Feature 通信模式及适用场景 |
| [ERROR_HANDLING.md](./ERROR_HANDLING.md) | `runTask(catching:)` 业务错误恢复与全局错误上报 |
| [TESTING_GUIDE.md](./TESTING_GUIDE.md) | 三层测试策略与 `TestStore` 用法 |
| [MULTI_FEATURE_GUIDE.md](./MULTI_FEATURE_GUIDE.md) | 购物 App + 车载 App 的完整联动示例 |
| [TIME_TRAVEL_GUIDE.md](./TIME_TRAVEL_GUIDE.md) | `TimeTravelRecorder` + `TimelineInspector` 使用指南 |
| [FEATURE_FLAG_GUIDE.md](./FEATURE_FLAG_GUIDE.md) | Feature Flag 集成方案 |

## 架构分析

| 文档 | 说明 |
|------|------|
| [ASYNC_RACE_AND_CANCELLATION.md](./ASYNC_RACE_AND_CANCELLATION.md) | latest-wins、协作取消与 root store 任务边界 |
| [ASYNC_FLOW_ANALYSIS.md](./ASYNC_FLOW_ANALYSIS.md) | Store / Middleware / Reducer / ScopedStore 的异步流分析 |
| [WHY_REDUX_ADOPTION.md](./WHY_REDUX_ADOPTION.md) | 为什么采用轻量 Redux，以及与裸 SwiftUI / TCA 的取舍 |
| [STRICT_CONCURRENCY_MIGRATION.md](./STRICT_CONCURRENCY_MIGRATION.md) | Swift 6 严格并发收口说明 |
| [ANALYSIS_AND_GUIDE.md](./ANALYSIS_AND_GUIDE.md) | 历史架构分析与改进思路，适合做设计回顾时参考 |

## 审阅与维护

| 文档 | 说明 |
|------|------|
| [REVIEW_REMEDIATION_REPORT.md](./REVIEW_REMEDIATION_REPORT.md) | 本轮 review 问题、修法与根因 |
| [IMPLEMENTATION_SCORECARD.md](./IMPLEMENTATION_SCORECARD.md) | 当前实现评分、已关闭项与后续优化清单 |

## 模块说明

- `TGReduxKit`：核心状态管理、异步原语、调试与测试工具。
- `TGNavigationStack`：已迁移到独立仓库 `https://github.com/tangzzz-fan/TGNavigationStack`，提供导航状态模型、`navigationReducer` 与 SwiftUI `TGNavigationStack` 适配层。
