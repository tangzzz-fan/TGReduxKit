# TGReduxKit Feature Flag Demo Guide

## 目标

本文档描述 `TGReduxKitDemo` 中 Feature Flag 综合示例的设计方式，重点说明：

- 如何让 Feature Flag SDK 保持在基础设施层
- 如何通过 middleware 把远端配置映射为显式 action 和 state
- 如何让业务 View 消费派生后的展示状态，而不是直接读取 SDK
- 如何把这套模式沉淀为后续 1.1.0 的可维护方案

## 为什么单独作为 1.1.0

`1.0.0` 解决的是框架核心稳定性问题，包括：

- `@MainActor Store`
- `ScopedStore`
- 轻量任务取消
- Debug middleware
- DI 协作边界

Feature Flag 综合接入属于上层集成能力扩展，不改变核心 API，但会增强 Demo、文档和推荐架构，因此更适合作为 `1.1.0` 的增量更新。

## 旧实现容易出现的问题

如果直接在业务 View 中查询 Feature Flag SDK，常见问题有：

- UI 条件分支散落在多个页面
- flag 变化无法进入统一状态流
- analytics、实验分组、降级策略难以统一治理
- 单元测试需要模拟 SDK，而不是测试纯状态变换

如果业务 View 直接读取 `FeatureFlagsState` 的底层字段，也会让页面层承担过多“配置来源”的知识。

因此，这次 Demo 采用两层边界：

1. `FeatureFlagsState` 只负责保存远端快照和刷新过程
2. `CatalogState` / `ShoppingState` 负责保存业务 View 真正消费的派生状态

## 模块设计

### 1. Redux.swift

- `FeatureFlagsState`
  - 保存远端快照、加载状态、最近刷新时间、刷新来源
- `FeatureFlagSnapshot`
  - 保存远端返回的原始功能开关值
- `CatalogState`
  - 持有 `showsFreeShippingBanner`
  - 持有 `showsRecommendedBadge`
  - 持有 `isPremiumCatalogOnly`
- `ShoppingState`
  - 持有 `isExpressCheckoutAvailable`
- reducer
  - 在 `.featureFlags(.loaded(...))` 中完成“远端快照 -> 业务展示状态”的单向映射

### 2. Middlewares.swift

- `FeatureFlagServicing`
  - 定义远端配置服务协议
- `DemoFeatureFlagService`
  - 提供 Demo 级别的轮换快照，方便演示刷新后的 UI 差异
- `makeFeatureFlagMiddleware`
  - 接收 `loadRequested`
  - 异步获取快照
  - 回写 `loaded(snapshot, date)`

### 3. Views.swift

- `FeatureFlagStatusCard`
  - 这是唯一显式展示 Feature Flag 状态的 View
  - 它读取 `FeatureFlagsState` 是合理的，因为它本身就是“配置看板”
- `ProductListView`
  - 不直接读取底层 flag snapshot
  - 只消费 `CatalogState` 的派生展示字段
- `ProductDetailView`
  - 只消费 `ShoppingState.isExpressCheckoutAvailable`
  - 不感知具体 flag key 或远端来源

## 数据流

```text
App Launch / Manual Refresh
        ↓
FeatureFlagsAction.loadRequested
        ↓
Feature Flag Middleware
        ↓
FeatureFlagServicing.fetchSnapshot()
        ↓
FeatureFlagsAction.loaded(snapshot, date)
        ↓
Reducer maps snapshot to presentation state
        ↓
CatalogState / ShoppingState updated
        ↓
Business Views render derived state
```

## 按模块 / 功能 + 时间的实施方案

| 阶段 | 模块 | 功能 | 时间 |
| --- | --- | --- | --- |
| Phase 1 | State | 建立 `FeatureFlagsState`、`FeatureFlagSnapshot`、派生展示字段 | 0.5d |
| Phase 2 | Middleware | 接入远端配置协议、刷新任务、启动加载 | 0.5d |
| Phase 3 | View | 增加配置看板、Banner、推荐标记、Express Checkout 分支 | 0.5d |
| Phase 4 | Test & Docs | 补充可见性测试、更新 changelog、沉淀说明文档 | 0.5d |

## 维护规则

后续如果继续扩展 Feature Flag，保持以下约束：

1. 业务 View 不直接依赖 Feature Flag SDK
2. 优先把 flag 结果映射为业务语言，而不是保留原始 key 到处传递
3. 允许单独的“配置看板”读取 `FeatureFlagsState`
4. reducer 负责派生状态，middleware 负责副作用
5. 同一类远端配置刷新统一走 `runTask(id:)`
6. 每新增一个重要 flag，都要补一条“快照 -> 业务状态”的测试

## Demo 当前覆盖的综合场景

- 启动加载 Feature Flag
- 手动刷新远端配置
- Banner 开关
- 推荐徽标开关
- Premium Catalog 过滤
- Express Checkout 行为开关
- scoped store 展示配置看板
- 业务页面消费派生状态

## 结论

这套示例的核心不是“在 View 里判断某个 flag”，而是：

- 用 middleware 管理远端配置生命周期
- 用 reducer 把 flag 转成业务语义状态
- 用业务 View 只读取派生结果

这样既保留了 TGReduxKit 的轻量边界，也让 Feature Flag 集成具备可测试性、可追踪性和可维护性。
