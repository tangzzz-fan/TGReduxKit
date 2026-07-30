# 异步竞态与任务取消（问题 A / B）

## 1. 文档目标

本文把「多个不确定的异步答案怎么进状态」拆成两个可操作问题，并说明 TGReduxKit 的解法边界：

| 代号 | 问题 | 一句话 |
|------|------|--------|
| **A** | 竞态 / 乱序完成 | 多次请求同时在飞，旧结果晚到时会不会污染 State？ |
| **B** | 取消与生命周期 | 过期任务怎么停？离开页面 / Store 释放时怎么办？ |

相关但不展开的主题见文末「相邻问题」。更完整的异步四层模型见 [ASYNC_FLOW_ANALYSIS.md](./ASYNC_FLOW_ANALYSIS.md)。

---

## 2. 问题细化

### 2.1 问题 A：多个不确定答案（竞态）

**输入特征**

- 同一次用户意图会触发**多次**异步请求（搜索连打、连续下拉刷新、快速切 Tab）。
- 请求完成时间**不确定**，先发不一定先回。
- 业务上通常只想保留**最新意图**对应的结果（latest-wins），而不是「谁先到谁写」。

**若不管理会发生什么**

```
用户输入:  "a"  →  "ab"  →  "abc"
请求发出:   R1      R2       R3
完成顺序:          R2 先回 → R3 回 → R1 最晚回
错误结果:  State 最终被 R1（"a"）覆盖，UI 显示错结果
```

**要区分的两件事**

1. **调度层**：旧任务还要不要继续跑？（取消 / 不取消）
2. **写入层**：旧任务若已跑完，还允不允许 `dispatch` 结果？（业务 gate）

TGReduxKit 在调度层提供 `runTask(id:)`；写入层要求调用方在 await 后检查 `Task.isCancelled`。两者缺一不可。

### 2.2 问题 B：取消与生命周期

**输入特征**

- 任务可能比页面 / Feature / Store 活得更久。
- 同 ID 的任务会被新任务替换，旧任务的「完成清理」可能和新任务的「注册」交错。
- 需要区分：**业务取消**（不要旧答案）与 **簿记取消**（不要弄脏 `managedTasks`）。

**若不管理会发生什么**

- 用户已离开搜索页，旧请求仍 `dispatch`，造成多余更新或对已释放对象操作。
- 旧任务在被取消后才执行 `removeValue`，误删**新任务**在字典里的登记，导致新任务无法再被取消。

---

## 3. 设计总览

```
View / Middleware
      │  dispatch(.searchQueryChanged)
      ▼
Middleware（同步洋葱）
      │  next(action)           → Reducer 立刻更新 loading / query
      │  runTask(id: "…")       → 同 ID 取消旧 Task，启动新 Task
      ▼
异步世界（Swift Concurrency）
      │  await work…
      │  guard !Task.isCancelled  → 丢弃过期答案（A 的写入层）
      │  await store.dispatch(result)
      ▼
再次进入洋葱 → Reducer 写入「确定答案」→ @Observable 刷新 UI
```

**原则**

- Reducer **只处理已确定的 Action**，不启动网络、不持有 Task。
- Middleware **同步签名、异步内容**：先 `next`，再 `runTask`。
- 所有 `dispatch` / 状态读写收敛在 `@MainActor`，并发完成的回流会串行化到主线程。

---

## 4. 问题 A 的解法：同 ID latest-wins

### 4.1 API

```swift
store.runTask(id: "catalog-search") {
    // 异步工作
}

store.cancelTask(id: "catalog-search")
store.cancelAllTasks()
```

- **有 ID**：启动前取消同 ID 旧任务，并登记到 `managedTasks`。
- **无 ID**：fire-and-forget，不参与取消表。
- **不同 ID**：互不取消，可并行（例如 `"catalog-search"` 与 `"feature-flags"`）。

`CancellationID` 是轻量 `Hashable` / `Sendable`，可用字符串字面量：`id: "catalog-search"`。

### 4.2 实现要点（调度层）

```swift
// Store.runTask — 同 ID 先取消再注册
if let id {
    cancelTask(id: id)
}
let token = UUID()
let task = Task { ... }
if let id {
    managedTasks[id] = ManagedTask(token: token, task: task)
}
```

### 4.3 写入层：协作式取消检查（必须）

Swift 的 `Task.cancel()` 是**协作式**的：不会魔法般拦截「已经算完、正要 dispatch」的代码。标准模式是 await 后的双检查点：

```swift
store.runTask(id: "catalog-search") {
    try? await Task.sleep(nanoseconds: 300_000_000)  // 可选：手动 debounce
    guard !Task.isCancelled else { return }

    let results = await searchService.search(query: query, in: products)
    guard !Task.isCancelled else { return }

    await store.dispatch(.catalog(.searchCompleted(query, results)))
}
```

| 检查点 | 作用 |
|--------|------|
| sleep / 网络前或后 | 被新输入取消后，尽早退出，少做无效工作 |
| `dispatch` 前 | 即使网络已返回，也不把过期答案写进 State |

Demo 实现见 `Examples/TGReduxKitDemo/.../Middlewares.swift` 的 `makeProductSearchMiddleware`。

### 4.4 声明式替代：`debounce`

若不想手写 sleep，可用内建原语（仍建立在 `runTask(id:)` 之上）：

```swift
store.debounce(id: "search", milliseconds: 300) {
    let results = await searchService.search(query)
    guard !Task.isCancelled else { return }
    await store.dispatch(.searchCompleted(results))
}
```

同类还有 `throttle`、带 retry / timeout / `catching` 的 `runTask` 变体，见 [ADVANCED_USAGE.md](./ADVANCED_USAGE.md)。

### 4.5 测试约定

库内已有行为验证：同 ID 慢任务 + 快任务 → State 只保留后者（`testRunTaskCancelsPreviousTaskWithSameID`）。业务侧建议对「取消后不得 dispatch」写一条中间件或集成测试，避免回归时漏掉 `guard`。

---

## 5. 问题 B 的解法：三层生命周期

### 5.1 第一层 — 显式取消

| API | 场景 |
|-----|------|
| `cancelTask(id:)` | 停掉某一类逻辑操作（例如清空搜索框） |
| `cancelAllTasks()` | 离开页面 / Feature 拆卸时统一清理已登记任务 |

只清理**带 ID 且登记成功**的任务；无 ID 的 `Task { }` 不在此表内。

### 5.2 第二层 — `[weak self]`

`runTask` 内部 Task 捕获 `[weak self]`，避免长时间网络把 Store 钉在内存里。Store 已释放时，收尾逻辑直接跳过，不会强行延长生命周期。

### 5.3 第三层 — Token（簿记正确性，不是业务过滤）

```swift
private struct ManagedTask {
    let token: UUID
    let task: Task<Void, Never>
}

private func finishTask(id: CancellationID, token: UUID) {
    guard let task = managedTasks[id], task.token == token else { return }
    managedTasks.removeValue(forKey: id)
}
```

**Token 解决的问题**：旧任务结束时的清理，不要误删新任务在 `managedTasks` 里的条目。

**Token 不解决的问题**：过期网络结果是否写入 State。那仍然靠 `Task.isCancelled`（问题 A 的写入层）。

`runTask(id:catching:)` 同样在取消后不生成 error Action，避免「取消」被误报成业务失败。

---

## 6. 场景走读：搜索框连打

以 Demo 购物目录搜索为例。

1. 用户输入 `"a"` → middleware `next` → reducer 更新 `query` / loading。
2. `runTask(id: "catalog-search")` 启动 Task₁（含 300ms sleep）。
3. 用户很快输入 `"ab"` → 再次 `runTask(id: "catalog-search")` → **取消 Task₁**，启动 Task₂。
4. Task₁ 在 sleep 或网络后 `guard` 失败，**不 dispatch**。
5. Task₂ 完成后 `dispatch(.searchCompleted("ab", …))`，State 与最新输入一致。
6. 若同时还有 feature flags 加载，使用 ID `"feature-flags"`，与搜索**并行、互不取消**。

这就是「多个不确定答案」在本库中的标准落点：**同一逻辑操作用同一 CancellationID；不同操作用不同 ID。**

---

## 7. 使用清单（团队约定）

做这类异步时，建议固定检查：

1. **给可重复的逻辑操作一个稳定 ID**（不要每个请求一个随机 ID，否则无法 latest-wins）。
2. **每个 await 边界后考虑 `guard !Task.isCancelled`**，至少在最终 `dispatch` 前一次。
3. **先 `next(action)` 再开 Task**，让 loading / 输入态立刻进 Reducer。
4. **页面 / Feature 退出时**对根 Store 调用 `cancelAllTasks()` 或按 ID 取消（ScopedStore **没有**任务 API，任务只挂在根 Store）。
5. **简单一次性副作用**可用裸 `Task { }`；需要竞态控制时改用 `runTask(id:)`。
6. **错误映射**优先 `runTask(id:catching:)`，并确认取消路径不会误报错。

---

## 8. 相邻问题（本文不展开）

| 类别 | 问法 | 去哪看 |
|------|------|--------|
| C 并发隔离 | 多类异步如何互不影响？ | 本文 §4.1 不同 ID；Demo 双 middleware |
| D Redux 边界 | 副作用放哪、谁写回 State？ | [ARCHITECTURE.md](../ARCHITECTURE.md)、本文 §3 |
| E 声明式控制流 | debounce / retry / timeout？ | [ADVANCED_USAGE.md](./ADVANCED_USAGE.md) |
| 跨 Feature 异步接力 | A 完成后触发 B？ | [CROSS_FEATURE_COMMUNICATION.md](./CROSS_FEATURE_COMMUNICATION.md) |

---

## 9. 一句话结论

**不确定答案用 `CancellationID` 收成「逻辑操作」；同 ID 在调度层 latest-wins；`Task.isCancelled` 在写入层丢掉过期答案；Token 只保证任务表簿记正确。库提供取消基础设施，业务仍需在 await 后显式 gate。**
