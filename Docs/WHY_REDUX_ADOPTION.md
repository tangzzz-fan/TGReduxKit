# 为什么转向 Redux：设计思路与团队采纳指南

> **适用版本**：TGReduxKit **5.0**（纯 Reducer + Middleware→`Effect`）。技术细节以源码与 [ARCHITECTURE.md](../ARCHITECTURE.md) 为准。

## 1. 文档目标

面向「要不要在团队里引入 TGReduxKit」的讨论：

1. **为什么**要从分散的 SwiftUI 状态转向单向数据流？
2. **为什么是这个库**（相对裸 `@State` / MVVM / TCA）？
3. **怎么落地**——用可讲清的业务场景串起来。

---

## 2. 定位

> **比裸 SwiftUI 状态更有纪律，比 TCA 更轻。**

| 痛点 | 分散状态常见表现 |
|------|------------------|
| 状态散落 | `@State` / 环境对象 / 单例混用 |
| 副作用散落 | View `task` / ViewModel 里直接打网络，竞态各写一套 |
| 协作成本 | 新人猜「谁改了什么」 |
| 可测性 | UI 与异步缠在一起 |
| 跨 Feature | 通知或互相持有引用 |

目标是把「发生了什么」和「状态怎么变」变成共享语言，而不是再上一套沉重框架。

---

## 3. 会上常见反对意见

| 反对意见 | 基于 5.0 的答复 |
|----------|----------------|
| 「SwiftUI 自带状态就够了」 | 单屏够；多 Feature + 异步回流需要 Action 轨迹与取消约定 |
| 「太像 TCA」 | 无 `DependencyValues`、无宏、无 Effect 代数；核心是 Store / Middleware / 纯 Reducer / `Effect` |
| 「已有 MVVM」 | 可并存：副作用进 Middleware，状态变更进 Reducer；View 读 `Store` / `ScopedStore` |
| 「异步还不是要写 Task？」 | Middleware 返回声明式 `Effect`；Store 按 `CancellationID` 调度 / 取消，约定统一 |
| 「迁移成本」 | 可按 Feature 渐进挂到根 Store |

**一句话提案**：事件 → Middleware（可选 `Effect`）→ 纯 Reducer → UI；依赖在 Composition Root 注入工厂，不进 Store。

---

## 4. 设计选择（可验证）

### 4.1 谁可以改状态

- 唯一写入：`dispatch` → Middleware 洋葱 → Reducer
- Reducer：`(inout State, Action) -> Void`，禁止 IO
- 副作用：Middleware 返回 `Effect`；Store 解释执行

### 4.2 主线程与并发

`Store` / Middleware 在 `@MainActor`；`Effect` 闭包 `@Sendable`；follow-up Action 回到主线程 `dispatch`。

### 4.3 Feature 隔离

`ScopedStore`：`scope(state:action:)` 投影局部状态。任务生命周期仍在根 `Store`（`managedTasks` / `Effect.cancel`）。

### 4.4 异步：latest-wins

同 `CancellationID` 的新 `.task` / `.debounce` 取消旧任务。细节见 [EFFECT_GUIDE.md](./EFFECT_GUIDE.md)。

### 4.5 DI 在门外

`ShoppingDependencies` + middleware 工厂（闭包捕获）。见 [DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md)。

### 4.6 SwiftUI

`@Observable` Store、`provideStore`、`binding(get:send:)`。协议名 `State` 与 SwiftUI 冲突时用 `@SwiftUI.State`。

### 4.7 刻意不做

| 不做 | 原因 |
|------|------|
| TCA 式 `@Dependency` | 编译期工厂注入即可 |
| Store 内置服务定位器 | Store 只做状态机 |
| 隐式全局单例 Store | 应用显式组装 |
| Time Travel 内置产品 | 5.0 Debug 提供 logging / diff / error reporting |

---

## 5. 选型对照

| 维度 | 裸 SwiftUI / VM | TGReduxKit 5.0 | TCA |
|------|-----------------|----------------|-----|
| 学习曲线 | 低 | 中低 | 高 |
| 状态可追踪 | 弱 | 强（Action） | 很强 |
| 异步约定 | 各自为政 | `Effect` + `CancellationID` | Effect 体系完善 |
| DI | 随意 | 工厂闭包 | `DependencyValues` |
| 适合 | 小、短生命周期 | 中小～中型 SwiftUI 产品 | 愿投入框架成本的大型团队 |

---

## 6. 落地路径

1. **对齐语言**：Action / 纯 Reducer / Middleware→Effect / Composition Root 注入  
2. **垂直切片**：一个 Feature（搜索或 Flag）+ mock 工厂测试  
3. **跨 Feature**：父级 Middleware 或 cross-cutting reducer（[CROSS_FEATURE_COMMUNICATION.md](./CROSS_FEATURE_COMMUNICATION.md)）  
4. **可选**：`TGReduxKitDebug` 中间件  

材料：`Examples/TGReduxKitDemo`。

---

## 7. 风险（诚实边界）

1. 需要纪律：忘记在长循环里看 `Task.isCancelled` 仍会出竞态  
2. 小 Feature 可能显得样板偏多——可先用本地 `@State`  
3. `ScopedStore` 不转发任务 API——取消挂在根 Store / Effect id  

---

## 8. 结论

多 Feature、多异步答案时，用同一套语言描述「发生了什么、状态怎么变、过期任务怎么丢」。5.0 用**纯 Reducer + Middleware→Effect + 工厂 DI**保持比 TCA 更轻，且与 Swift 6 / Observation 对齐。

## 相关文档

- [ARCHITECTURE.md](../ARCHITECTURE.md)
- [ADR_AUDITED_MIDDLEWARE_EFFECT.md](./ADR_AUDITED_MIDDLEWARE_EFFECT.md)
- [DEPENDENCY_INJECTION.md](./DEPENDENCY_INJECTION.md)
- [EFFECT_GUIDE.md](./EFFECT_GUIDE.md)
- [TESTING_GUIDE.md](./TESTING_GUIDE.md)
- [MIGRATION_4_TO_5.md](./MIGRATION_4_TO_5.md)
