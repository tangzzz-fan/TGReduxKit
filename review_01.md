# TGReduxKit Swift 6 严格并发收口与修复报告

**版本**：V2.0  
**日期**：2026-08  
**定位**：记录本轮基于人工 review + OCR 的问题清单、修复落地、设计收口，以及修复后相较旧架构的收益。

---

## 一、结论摘要

本轮修复不是单点 bugfix，而是一次围绕 **Swift 6+ 严格并发环境** 的系统性收口。

最终结果：

1. `Reducer` 已正式收口到 `@MainActor`
2. `combineReducers` / `pullback` / `navigationReducer` 一并对齐到 `@MainActor`
3. 仓库内 Demo / 测试 / 组合器全部改齐，不再混用“主 actor Store + 非隔离 Reducer”
4. 同时修掉了异步原语、任务生命周期、observer 重入、time travel 边界等一批由 review 挖出来的实现问题

一句话总结：

> **TGReduxKit 现在明确是一套面向 Swift 6+ 严格并发、以 MainActor 为状态演进边界的 Redux 风格状态管理库。**

---

## 二、本轮 review 挑出了什么问题

### 1. 并发契约不闭合

原来仓库的核心定义是：

- `Store` 是 `@MainActor`
- `Middleware` 是 `@MainActor`
- `Reducer` 却还是普通闭包

这会在 Swift 6 严格并发下导致模块级 reducer 常量报错，例如：

```swift
public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = ...
```

编译器会认为这个全局 `let` 持有的是一个非 `Sendable`、非全局 actor 隔离的函数值，因此不满足并发安全要求。

这不是文档表达问题，而是**公开 API 契约本身不闭合**。

### 2. `throttle` 名义存在，语义缺失

`throttle(id:milliseconds:)` 原实现里没有真正判断节流窗口是否已开启，导致它实际上每次都会执行，不符合注释承诺的行为。

### 3. `runTask(id:)` 的取消只是“发信号”，不是“完成切换”

旧实现里，新任务会在取消旧任务后立刻启动；但 Swift 任务取消是协作式的，旧任务如果没及时退出，就可能和新任务重叠运行。

### 4. `TimeTravelRecorder` 对边界条件假设过强

主要问题包括：

- `maxEntries` 裁剪后 `index` 会重复
- `snapshot(at:)` 依赖数组位置，不是逻辑 timeline index
- `initialState` 依赖当前 entries 首项
- 负值 `maxEntries` 会导致运行时风险
- `exportJSON()` 吞掉 action 编码错误

### 5. observer / scope 生命周期假设过乐观

旧代码默认：

- observer 通知过程中不会同步重入
- scoped store 对父 store 的访问如果失效，直接 `fatalError`

这些在库层都太脆，会把边界情况直接升级成崩溃或状态覆盖。

### 6. API 细节和新并发模型不完全对齐

比如：

- `Dispatch` 命名与系统 `Dispatch` 模块冲突
- 文档示例没有完全反映新的 actor / async 约束
- 测试里仍存在大量裸 `(inout State, Action) -> Void`，绕开了正式的 `Reducer` 契约

---

## 三、这次具体修复了哪些问题

### A. 严格并发 / actor 契约收口

已完成：

1. `Reducer` 改为：

```swift
public typealias Reducer<State, Action> = @MainActor (inout State, Action) -> Void
```

2. `combineReducers(_:)` 标记为 `@MainActor`
3. `pullback(_:state:extract:)` 标记为 `@MainActor`
4. `pullback` 的 `extract` 闭包也同步收口到 `@MainActor`
5. `navigationReducer` 改为 `@MainActor`
6. Demo 和测试里的 reducer 声明统一切回 `Reducer<...>`

这部分修复解决的是：

- Swift 6 严格并发下全局 reducer 常量诊断
- 组合器在 actor 隔离语义上的半闭合状态
- 仓库自身与对外契约不一致的问题

### B. 异步原语与任务生命周期

已完成：

1. 修复 `throttle` 真正按窗口忽略重复调用
2. `runTask(id:)` 现在会等待被取消的旧任务结束后再启动新任务
3. 直接取消返回的 `Task` 句柄时，也会清理内部 `managedTasks`

解决的是：

- 节流 API 名实不符
- 同 ID 任务重叠运行
- stale task / ghost task 残留

### C. Store / ScopedStore 的重入与生命周期

已完成：

1. observer 通知改为基于快照遍历
2. 失效 observer 在遍历中清理
3. `scope` 的 `stateProvider` 不再通过弱引用失效后 `fatalError`

解决的是：

- 同步重入时 observer 被覆盖
- 父 store 生命周期边界直接崩溃

### D. Time Travel / Debug 基建

已完成：

1. 使用独立 `nextIndex`，保证 timeline index 单调递增
2. `snapshot(at:)` 改为按逻辑 index 查询
3. `initialState` 独立保存
4. `maxEntries` 负值钳制并即时裁剪
5. `exportJSON()` 传播 action 编码错误
6. 文档明确“引用语义 state 的 snapshot 前提”

解决的是：

- timeline identity 错乱
- 裁剪后调试信息失真
- 导出静默降级

### E. API 与文档同步

已完成：

1. `Dispatch` 重命名为 `ActionDispatcher`
2. `Middleware` 注释示例对齐新的 async / actor 模型
3. `Reducer` 注释更新为严格并发口径
4. 测试类型注解改齐，避免仓库内部继续走旧路

---

## 四、为什么是这样修，而不是只补局部 workaround

### 1. actor 问题的本质不是“能不能编译”，而是“公开契约是否一致”

如果继续保持：

- `Store` / `Middleware` 是 `@MainActor`
- `Reducer` 是普通闭包

那库其实是在对外暴露两个互相打架的并发故事：

1. 运行时状态流在主 actor 上
2. 但最核心的状态演进函数却不是主 actor 契约的一部分

这在 Swift 6 之前可能只是“看起来有点别扭”，到了严格并发下就会变成真实的 API 问题。

所以这次不再停在“文档解释一下”，而是直接把 `Reducer` 收口到 `@MainActor`。

### 2. 异步问题的本质不是“有没有 cancel”，而是“替换是否真正完成”

`Task.cancel()` 不是同步销毁。

如果新任务在旧任务尚未退出时立刻启动，库层就没有兑现“同一 `CancellationID` 只应有一个活跃任务”的语义。

因此修复不是简单补一个 `guard !Task.isCancelled`，而是把任务切换语义真正落到“先结束旧任务，再进入新任务”。

### 3. Debug 工具的本质不是“看起来能用”，而是“调试坐标系必须稳定”

一旦 timeline index 会重复、snapshot 不再对应逻辑 index，整个 time travel 的定位能力就会失真。

所以这部分修复不是 cosmetic，而是在修 debug 基础设施的“坐标系”。

### 4. 生命周期问题的本质是库边界不该用崩溃掩盖状态设计问题

`fatalError` 在 demo 里有时看起来简单，但在库里意味着把状态所有权问题直接甩给接入方。

这次改法的方向，是让 scope / observer 的边界行为先变成稳定语义，再由上层决定要不要暴露诊断。

---

## 五、修正后的代码架构设计

### 新的核心模型

现在 TGReduxKit 的核心边界可以概括成：

1. **状态演进边界**：`Store` / `Reducer` / `Middleware` / reducer composition 都在 `@MainActor`
2. **异步副作用边界**：通过 `runTask` / `Task` 脱离主 actor 执行耗时工作
3. **状态回流边界**：异步完成后再通过 `dispatch` 回到主 actor 状态流

也就是：

```text
UI / View
  -> dispatch(action)
  -> Middleware (@MainActor)
  -> Reducer (@MainActor)
  -> Store.state mutation (@MainActor)

异步工作:
Middleware / Store.runTask
  -> async work off main actor
  -> await dispatch(follow-up action)
  -> back to MainActor state flow
```

### 相比旧代码的好处

#### 1. 并发语义闭合了

旧代码：

- Store 在主 actor
- Reducer 不在主 actor
- 组合器没有统一 actor 语义

新代码：

- 整个 reducer pipeline 统一在主 actor
- Swift 6 编译器和库设计表达的是同一个事实

#### 2. 接入方不再承担额外并发补丁

旧代码下，业务侧需要：

- 给全局 reducer 手动补 `@MainActor`
- 或想办法回避严格并发诊断

新代码下，库层直接承担这份契约，接入方按自然写法即可。

#### 3. 异步工具更可信

旧代码下，`throttle`、`runTask(id:)` 都存在“看起来有 API，实际上语义不完整”的问题。

新代码下：

- 节流真正节流
- 同 ID 任务替换真正串行
- 任务取消残留也被清理

#### 4. debug 基建从“能展示”变成“能定位”

旧代码的 time travel 更像一个展示器；
新代码的 time travel 才真正具备稳定的 timeline identity 和 snapshot 语义。

#### 5. 生命周期边界更稳

旧代码在 observer / scoped store 边界更依赖“理想用法”；
新代码对重入、失效 observer、父 store 生命周期都更稳健。

---

## 六、旧架构和新架构的本质区别

最本质的区别不是“多了几个 `@MainActor`”。

真正的区别是：

### 旧架构

更像是：

> **运行时大体在主线程上，但类型系统没有完全承认这一点。**

### 新架构

现在变成：

> **运行时状态流、公开类型契约、Swift 6 编译器检查，三者都在描述同一个 MainActor 模型。**

这就是这次修复真正的价值。

---

## 七、当前状态

截至本次修复结束：

1. `Reducer @MainActor` 收口已完成
2. 组合器 / 导航 reducer / Demo / 测试已同步改齐
3. `swift build` 通过
4. `swift test` 通过
5. 严格并发最小复现已验证通过

因此，`review_01.md` 最初指出的 actor 问题，**现在已经从“讨论建议”变成“代码落地完成”**。
