# TGReduxKit 实现评分与优化路线

## 说明

本文档基于本轮严格并发收口与异步 / 生命周期修复完成后的全库审阅，给出：

1. 分维评分
2. 优先优化建议
3. 建议落地顺序
4. 刻意不做的事项

配套上下文：

- 修复过程：[`REVIEW_REMEDIATION_REPORT.md`](./REVIEW_REMEDIATION_REPORT.md)
- 并发边界：[`STRICT_CONCURRENCY_MIGRATION.md`](./STRICT_CONCURRENCY_MIGRATION.md)

**审阅基线**：`3.0.0` 合并后 + Store 协议统一与导航能力外置（相对修复前约 7.2 → 当前约 **9.0 / 10**）
**验证**：`swift build` / `swift test`（75 tests）通过
**规模**：Sources ~1.5k LOC，Tests ~2k LOC

---

## 综合结论

> 库已从「运行时大致在主线程、类型系统未完全承认」收口为完整的 MainActor 状态流模型。
> 剩余问题主要是产品化打磨（文档分层、异步语义说明、root/scoped 能力边界），不是架构方向错误。

| 指标 | 值 |
|------|-----|
| 综合分 | **9.0 / 10** |
| 最高维 | 架构 9.0 |
| 最低维 | Docs & DX 7.5 |
| 测试 | 75 通过 |

---

## 分维评分

| 维度 | 分 | 说明 |
|------|-----|------|
| 架构清晰度 | 9.0 | `Store → Middleware onion → Reducer → @Observable` 边界清晰；`scope` / `pullback` / `combineReducers` 组合模型克制；零外部依赖，Core 体量可控 |
| 并发正确性 | 8.5 | `Reducer` / composition / `Middleware` 同属 `@MainActor`；`runTask` 替换等待旧任务完成 + token 防误清。协作取消仍是调用方责任（合理） |
| API 设计 | 9.0 | `ActionDispatcher` 命名冲突已解；`StoreType` 已统一 `Store` / `ScopedStore` 的 `state`、`dispatch`、`binding` 与 `provideStore` 接口；导航状态模型与 `TGNavigationStack` 已迁移到独立仓库。root-only async 边界已明确写入 API 注释与文档 |
| 异步原语 | 8.3 | throttle 名实、runTask 串行替换已可信；root/scoped 责任边界已明确。timeout / throttle 与 in-flight 重叠仍依赖协作取消，语义继续保持克制 |
| 测试 | 9.1 | 本轮边界有回归覆盖；新增 `binding` KeyPath、导航 `.setPath`、Equatable 无变化跳过通知等测试。`TestStore` 已改为抛出结构化错误，更适合 Swift Testing / XCTest 报告 |
| Debug / Time Travel | 8.5 | timeline index、`snapshot(at:)`、`initialState`、`maxEntries`、`exportJSON` 坐标系已修稳 |
| Docs & DX | 8.4 | 入口已分为接入指南 / 架构分析 / 审阅维护三层，README 只保留分层入口。仍有少量历史分析文档可继续瘦身 |
| SwiftUI / Observation | 8.9 | `@Observable` 接入自然；`binding(get: KeyPath, send:)` 已补齐；导航事件已回到 reducer；`Equatable` 无变化可跳过多余通知；`StoreType` 已统一 View 依赖面，且 root-only async 边界已明确 |

---

## 本轮已关闭（不再作为优化项）

以下问题已在本轮修复中收口，本文档不再列为待办：

1. `Reducer` / 组合器 MainActor 契约
2. `throttle` 窗口名实一致
3. `runTask(id:)` 同 ID 替换串行化与句柄取消清理
4. observer 通知快照遍历
5. scope 父生命周期不再 `fatalError`
6. Time Travel 坐标系与导出错误传播
7. `Dispatch` → `ActionDispatcher` 命名
8. `Store` middleware dispatch 管道改为初始化时 compose 一次
9. `Store` / `ScopedStore` 已补 `binding(get: KeyPath, send:)` 重载
10. `TGNavigationStack` 的 path / dismiss 事件已回到 reducer
11. `Store` / `ScopedStore` 已在 `State: Equatable` 且值不变时跳过多余通知
12. 导航状态模型与 SwiftUI 适配层已拆到独立仓库 `TGNavigationStack`
13. `StoreType` 已统一 `Store` / `ScopedStore` 的基础 SwiftUI API 面
14. root-only async 边界已明确：`runTask` / `debounce` / `throttle` / retry / timeout 不下放到 `ScopedStore`
15. `TestStore` 已从 `fatalError` 切换为结构化断言错误
16. `Docs/` 已补入口分层，README 降为目录入口

详见 [`REVIEW_REMEDIATION_REPORT.md`](./REVIEW_REMEDIATION_REPORT.md)。

---

## 优先优化清单

Effort：`S` &lt; 半天，`M` ≈ 1–2 天。

| Priority | Area | 优化项 | 原因 | Effort |
|----------|------|--------|------|--------|
| **P2** | Async | `throttle` / `timeout` 协作取消语义文档化或收紧 | 窗口锁与 in-flight 重叠、timeout 竞态仍依赖协作取消，调用方易误用 | S |
| **P3** | Docs | 历史分析文档继续瘦身或补“历史基线”标识 | 入口已分层，但少量长文仍保留旧时期上下文 | M |

---

## 建议落地顺序

### 1. 观测与热路径验证（P1）

**目标**：减少无意义重绘与每次 dispatch 的分配。

**做法建议**：

1. 当 `State: Equatable` 时，仅在新值 `!=` 旧值时赋值（含 `ScopedStore.refreshStateFromParent`）
2. 如有需要，用基准或 Demo 列表滚动场景验证重绘次数

**收益**：列表高频 dispatch、多 scope 场景更稳。

### 2. Root / Scoped 能力边界（已完成）

**目标**：Feature View 不感知 root / scoped 差异。

**做法建议**：

1. 已基于 `StoreType` 明确共享公共面：`state` / `dispatch` / `binding` / `provideStore`
2. 已明确选择 **B**：文档硬性规定「异步副作用只走 root store」
3. README / Guides / API 注释中已区分“任何 store 都能做什么”和“只有 root store 能做什么”

**收益**：Demo 与接入方样板代码显著减少。

### 3. 测试与异步语义打磨（进行中）

1. `TestStore.assert` 已切换为抛出结构化错误，并由测试框架接管失败报告
2. 在 [`ASYNC_RACE_AND_CANCELLATION.md`](./ASYNC_RACE_AND_CANCELLATION.md) 或 API 注释中写清：
   - throttle 是 leading-edge + 窗口锁，不保证与 in-flight 互斥
   - timeout 依赖协作取消；`operation` 内必须检查 `Task.isCancelled`
3. 按需继续补 1–2 个边界测试锁定文档语义

### 4. 文档收敛（首轮已完成）

1. 已区分「接入指南」与「内部分析 / review 报告」
2. README 已改为三层入口；分析类文档保留但降低入口权重
3. 后续继续避免堆叠重复长文，优先短链到源码注释

---

## 刻意不做

以下事项**不应**为了「对标 TCA」或抬分而引入：

1. CasePaths / 宏生成 action 路由
2. Effect reducer / 结构化 Effect 系统
3. 库内置依赖注入容器（继续保持 DI 外置 + Middleware 工厂）
4. 为细粒度观测引入完整 ViewStore 框架（除非真实产品出现可测瓶颈）

理由：会偏离「SwiftUI 与 TCA 之间的轻量 Redux」定位，并失去当前 &lt;2k LOC Core 的优势。

---

## 下一跳目标

| 阶段 | 目标分 | 主要动作 |
|------|--------|----------|
| 当前 | 9.0 | 严格并发、导航单向流、导航仓库外置、StoreType 统一协议已收口 |
| 下一跳 | ~9.2 | 继续补异步语义边界测试，瘦身历史分析文档 |
| 再往后 | 9.0+ | P2/P3 打磨；仅在真实瓶颈出现时加深 Observation |

---

## 验收清单（落地时使用）

完成对应优先级后，建议至少满足：

- [x] `swift build` / `swift test` 全绿
- [x] P0：导航 dismiss / pop 有 action 路径；time-travel 可录到
- [x] P1：Equatable 无变化不触发多余 `@Observable` 通知（有测试或可复现 Demo）
- [ ] P1：middleware 管道只 compose 一次（可读性注释或单测可观察）
- [x] P1：`Store` / `ScopedStore` 对 View 的使用面一致，且文档明确 root-only async 策略
- [ ] `CHANGELOG.md` `[Unreleased]` 已记录行为变更（尤其导航与 API）

---

## 一句话

> 本轮修的是边界契约；下一轮优化应优先修导航单向流与观测热路径，而不是再加抽象层。
