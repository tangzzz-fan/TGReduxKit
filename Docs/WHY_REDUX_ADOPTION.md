# 为什么转向 Redux：设计思路与团队采纳指南

## 1. 文档目标

本文面向「在公司里要不要引入 TGReduxKit」的讨论，回答三件事：

1. **为什么**要从「各写各的 SwiftUI 状态」转向更有纪律的单向数据流？
2. **为什么是这个库**（相对裸 `@State` / 自研 ObservableObject / TCA）？
3. **怎么说服同事、怎么落地**——用一个可讲清的业务场景串起来。

技术细节以仓库源码与 [ARCHITECTURE.md](../ARCHITECTURE.md) 为准；异步竞态见 [ASYNC_RACE_AND_CANCELLATION.md](./ASYNC_RACE_AND_CANCELLATION.md)。

---

## 2. 先对齐：我们不是在「为了 Redux 而 Redux」

TGReduxKit 的定位是：

> **比裸 SwiftUI 状态更有纪律，比 TCA 更轻。**

它解决的不是「SwiftUI 不能写 App」，而是团队规模变大后反复出现的几类痛：

| 痛点 | 裸 SwiftUI / 分散 ObservableObject 常见表现 |
|------|---------------------------------------------|
| 状态散落 | View 里 `@State`、父组件传入、单例、环境对象混用，谁改了什么说不清 |
| 副作用散落 | `task` / `onAppear` / ViewModel 方法里直接打网络，竞态与取消各写一套 |
| 协作成本 | 新人改一个流程要猜「状态在哪、谁会改」；Code Review 缺少结构 |
| 可测性 | UI 与异步缠在一起，单测要么很重要么不敢测 |
| 跨 Feature | 购物车改了要刷推荐、Flag 改了要改展示——靠通知或互相持有引用，耦合上升 |

转向「轻量 Redux」的目标是：**把「发生了什么」和「状态怎么变」变成团队共享语言**，而不是引入又一个沉重框架。

---

## 3. 场景：说服同事——购物 App 的一周事故复盘

下面用一个虚构但贴近现实的场景，当作对内分享 / ADR 的叙事骨架。

### 3.1 背景

团队做 SwiftUI 购物 App：目录搜索、购物车、Feature Flag、推荐流。三人并行开发，约定「各自 Feature 一个 ViewModel」。

### 3.2 本周暴露的问题

1. **搜索竞态**：连打字时偶发显示旧关键词结果；各 Feature 的 debounce / cancel 写法不一致，有的忘了 `Task.isCancelled`。
2. **Flag 与 UI 打架**：某同学在 View 里直接读 SDK；另一同学在 ViewModel 缓存快照——同一屏两种真相。
3. **加购后推荐不刷新**：购物车 ViewModel 不知道推荐 ViewModel；加了 `NotificationCenter`，调试时难跟。
4. **测试推不动**：要测「加购 → 推荐刷新」，只能起 UI 测试或大量 mock View。

### 3.3 会上常见反对意见，以及对应答复

| 反对意见 | 可回应的点（基于本库设计） |
|----------|---------------------------|
| 「SwiftUI 自带状态就够了」 | 单屏够；多 Feature、异步回流、跨模块联动时，缺统一的 Action 轨迹与取消约定。 |
| 「再套一层太重，像 TCA」 | 核心类型极少（Store / ScopedStore / Reducer / Middleware / CancellationID）；无 Effect 代数、无 CasePath 强制体系；Demo + 文档可一周内上手。 |
| 「我们已有 MVVM」 | 可并存：ViewModel 可逐步收成「对 ScopedStore 的薄封装」，或直接让 View 读 `ScopedStore`。关键是副作用进 Middleware、状态变更进 Reducer。 |
| 「异步还不是要自己写 Task？」 | 是。库不假装消灭异步，而是提供 `runTask(id:)` + 原语，把竞态 / 取消变成**统一约定**，而不是每人一套。 |
| 「迁移成本」 | 可按 Feature 渐进：先一个 Store 挂根，一个 Feature `scope` 进去；不必 Big Bang。 |

### 3.4 提案一句话

> 用 TGReduxKit 把「事件 →（可选副作用）→ 纯状态变换 → UI」固定下来；异步用同一套 CancellationID；Feature 用 ScopedStore 隔离；跨 Feature 用显式 Action / 父级 Middleware，而不是隐式通知。

---

## 4. 设计思路：这个库「好」在哪里

下面按「说服工程负责人」的角度，列可验证的设计选择（不是口号）。

### 4.1 边界清晰：谁可以改状态

- **唯一写入路径**：`dispatch(Action)` → Middleware 洋葱 → Reducer。
- **Reducer 纯函数**：`(inout State, Action) -> Void`，无网络、无日志、无启动 Task。
- **副作用在 Middleware**：同步签名，内部再开 `Task` / `runTask`；结果再以 Action 回流。

好处：Code Review 可问「这个网络调用为什么出现在 Reducer / View？」——有明确否决标准。

### 4.2 主线程收敛，降低并发心智

`Store` / `dispatch` / Middleware 标注 `@MainActor`。异步 Task 里 `await store.dispatch(...)` 由 Swift 并发调度回主线程。

好处：不必在业务里维护「锁 + 回调线程」故事；状态变换相对其他 dispatch 是串行的。

### 4.3 Feature 隔离不靠拆多个全局单例

`ScopedStore`：`store.scope(state:action:)` 投影局部 State、映射局部 Action，支持嵌套。

好处：

- View 只依赖本 Feature 的状态形状。
- 根状态仍是单一数据源，跨 Feature 协调仍有「父级」可挂 Middleware / cross-cutting reducer。
- 比「每个 Feature 一个单例 Store」更好拼、更好测。

### 4.4 异步：轻量但够用的取消模型

- 同 `CancellationID` → latest-wins 取消旧任务。
- Token 保证任务表清理不错位。
- `debounce` / `throttle` / retry / timeout / `catching` 建立在同一原语上。

好处：搜索竞态这类「多个不确定答案」有标准答案，可写进团队规范（详见 [ASYNC_RACE_AND_CANCELLATION.md](./ASYNC_RACE_AND_CANCELLATION.md)）。

### 4.5 DI 在门外：Store 不吞容器

依赖通过 **middleware 工厂参数**注入（Demo 中的 `ShoppingDependencies`），而不是塞进 Store。

好处：测试可换假服务；生产可换真 SDK；Store 保持「状态机」，不变成服务定位器。

### 4.6 与 SwiftUI 贴合，而不是对抗

- `@Observable` 驱动刷新。
- `provideStore` / Environment 注入。
- `binding(get:send:)` 把字段桥成 `Binding`，输入控件仍单向数据流。
- 可选 Navigation 模块、时间旅行调试中间件——需要再挂，不挂零成本。

### 4.7 模块化状态树可演进

`combineReducers` + `pullback`：Feature reducer 可独立编写再组合；跨切逻辑放 cross-cutting reducer。

好处：目录 / 购物车 / Flag 可分人维护，仍汇合到一棵 State 树。

### 4.8 刻意不做的事（也是卖点）

| 不做 | 原因 |
|------|------|
| 完整 TCA Effect / Reducer 协议栈 | 保持 API 面与学习曲线可控 |
| Store 内置 DI 容器 | 避免框架绑架应用架构 |
| 隐式全局单例 Store | 单一数据源由应用显式创建并注入 |
| 自动吞掉所有 stale dispatch | 协作式取消更透明；强制业务写 `guard` |

说服时要诚实：**轻量意味着约定多于魔法**。团队需要接受「Action 命名、Reducer 纯度、CancellationID」这些纪律。

---

## 5. 和常见方案怎么比（对内选型表）

| 维度 | 裸 SwiftUI / 分散 VM | TGReduxKit | TCA |
|------|---------------------|------------|-----|
| 学习曲线 | 低 | 中低 | 高 |
| 状态可追踪 | 弱 | 强（Action 轨迹） | 很强 |
| 异步取消约定 | 各自为政 | `runTask(id:)` + 文档约定 | Effect 体系完善 |
| 代码量 / 仪式感 | 少 | 少～中 | 高 |
| 测试 Reducer | 难拆 | 易（纯函数） | 易（且工具链重） |
| 适合团队 | 小、短生命周期 | 中小～中型 SwiftUI 产品 | 大型、愿投入框架成本的团队 |
| 外部依赖 | 无 | 无 | 依赖 TCA 生态 |

**选型建议（可写进 ADR）**

- 单 Feature、几乎无跨模块异步 → 继续 SwiftUI 本地状态即可。
- 多 Feature、要统一竞态 / 调试 / 测试 → 优先评估 TGReduxKit。
- 已深度绑定 TCA 或需要其完整工具链 → 不必为换而换。

---

## 6. 怎么做：落地路径（为什么之后的「怎么做」）

### 6.1 阶段 0 — 对齐语言（半天）

组织一次短分享，只讲四样东西：

1. Action = 发生了什么  
2. Reducer = 状态怎么变  
3. Middleware = 副作用入口  
4. `runTask(id:)` = 同类异步 latest-wins  

材料：本仓库 Demo + 本文 §3 场景。

### 6.2 阶段 1 — 垂直切片（1～2 周）

选**一个**痛点 Feature（建议搜索或 Flag）：

1. 定义 `FeatureState` / `FeatureAction` / reducer。  
2. 挂到根 `AppState`，用 `scope` 注入该 Feature 的 View。  
3. 网络进 middleware，`runTask(id:)` 处理竞态。  
4. 为 reducer 写几个纯函数单测；中间件用假服务测取消行为。

成功标准：该 Feature 的「旧结果覆盖新结果」类 bug 有回归测试；新人能指着 Action 说明一次搜索的生命周期。

### 6.3 阶段 2 — 跨 Feature 约定（按需）

从三种模式里选（见 [CROSS_FEATURE_COMMUNICATION.md](./CROSS_FEATURE_COMMUNICATION.md)）：

- 父级 Middleware 转发  
- Reducer 内联联动  
- 显式协调 Action  

禁止再新增「Feature 互持 ViewModel + 通知」作为默认方案。

### 6.4 阶段 3 — 工程化增强（可选）

- Debug：`actionLoggingMiddleware` / `stateDiffMiddleware` / 时间旅行。  
- 错误：`runTask(catching:)` + 上报中间件。  
- Flag：SDK 留在基础设施层，只把派生展示状态放进 State（见 [FEATURE_FLAG_GUIDE.md](./FEATURE_FLAG_GUIDE.md)）。

### 6.5 迁移原则

- **渐进**：旧 ViewModel 可暂时 dispatch 到 Store，或读 ScopedStore，不必一夜重写。  
- **边界优先**：先规定「新代码默认走 Store」，旧代码碰触时再迁。  
- **度量**：用「竞态 bug 数、跨 Feature 改动的文件数、Reducer 单测覆盖」而不是「是否用了框架」当 KPI。

---

## 7. 有什么好处（可写进立项材料）

| 好处 | 谁感知 | 如何验证 |
|------|--------|----------|
| 状态变更可叙述 | 开发 / Review | 任意流程能列出 Action 序列 |
| 异步竞态有标准解法 | 开发 / QA | 同 ID 取消 + `isCancelled` 清单；相关 bug 下降 |
| Feature 边界清晰 | 多人协作 | View 只依赖 ScopedStore；根 State 聚合 |
| Reducer 易测 | 开发 | 无 UI 的纯函数测试秒级跑完 |
| 调试可插拔 | 排障 | Debug 中间件 / 时间旅行按需挂载 |
| 框架锁定低 | 架构 | 零第三方依赖；核心 API 面小，迁出成本可控 |

---

## 8. 风险与诚实边界

引入时主动说明，反而更容易过审：

1. **需要纪律**：忘记 `guard !Task.isCancelled` 仍会写出竞态；库不替你「自动正确」。  
2. **样板代码**：每个 Feature 有 State / Action / Reducer / 可选 Middleware——小 Feature 可能显得「重」，可用本地 `@State` 直到真正需要共享与异步约定。  
3. **不是银弹**：动画驱动的瞬时 UI、纯展示组件不必全部进全局 State。  
4. **ScopedStore 无任务 API**：取消挂在根 Store——团队要知道「谁负责 `cancelAllTasks`」。

---

## 9. 对内沟通模板（可直接粘贴）

**标题**：提议在 SwiftUI 客户端用 TGReduxKit 统一多 Feature 状态与异步约定  

**问题**：多 Feature 下状态与副作用分散，搜索竞态 / Flag 双真相 / 跨模块通知已造成缺陷与协作成本。  

**方案**：引入轻量单向数据流库 TGReduxKit（自研/内部依赖，零第三方）。先做搜索（或 Flag）垂直切片，再用 ScopedStore 扩展。  

**为何不是 TCA**：我们需要纪律与可测性，但不需要完整 Effect 代数与高仪式感；本库核心类型很少，与 Observation / MainActor 对齐。  

**成功标准**：切片 Feature 的竞态有测试；跨 Feature 默认走 Action；两周内第二名同学能独立加一个 middleware。  

**回滚**：切片 Feature 可保留旧 VM 分支；框架可移除，State/Action 形状仍可指导后续自研。  

---

## 10. 一句话结论

**转向 Redux（本库）不是为了追潮流，而是为了在多 Feature、多异步答案的产品里，用同一套语言描述「发生了什么、状态怎么变、过期任务怎么丢」。TGReduxKit 的设计优势在于：边界清楚、主线程收敛、Scoped 隔离、取消约定统一、DI 外置、对 SwiftUI 友好，且刻意保持比 TCA 更轻——适合作为公司内「可说服、可渐进、可测试」的状态管理默认选项。**

---

## 相关文档

- [ARCHITECTURE.md](../ARCHITECTURE.md) — 架构原则  
- [ASYNC_RACE_AND_CANCELLATION.md](./ASYNC_RACE_AND_CANCELLATION.md) — 竞态与取消（问题 A/B）  
- [ASYNC_FLOW_ANALYSIS.md](./ASYNC_FLOW_ANALYSIS.md) — 异步流深挖  
- [MULTI_FEATURE_GUIDE.md](./MULTI_FEATURE_GUIDE.md) — 多 Feature 实战  
- [TESTING_GUIDE.md](./TESTING_GUIDE.md) — 测试策略  
- [ANALYSIS_AND_GUIDE.md](./ANALYSIS_AND_GUIDE.md) — 能力边界与演进  
