# TGReduxKit 本轮 Review 与修复报告

## 说明

这份文档记录本轮人工 review 与 OCR 审查挖出的核心问题、修复方式，以及为什么这些问题本质上不是零散 bug，而是同一批架构边界没有完全收口。

## 本轮发现了什么问题

### 1. 严格并发契约不闭合

`Store` / `Middleware` 已经在 `@MainActor`，但 `Reducer` 之前不是。这会把 Swift 6 严格并发问题外溢给接入方。

### 2. `throttle` 名义存在，行为不完整

旧实现没有真正检查节流窗口，同一窗口内的重复调用并不会被抑制。

### 3. `runTask(id:)` 替换语义不完整

旧任务被取消后，新任务会立刻启动；但取消是协作式的，所以旧任务可能继续运行并和新任务重叠。

### 4. observer / scope 生命周期边界太脆

旧代码在 observer 通知重入和 scoped store 的父生命周期边界上都更依赖理想用法，异常时容易覆盖状态或直接崩溃。

### 5. Time Travel 的坐标系不稳定

旧实现存在：

1. timeline index 裁剪后重复
2. `snapshot(at:)` 依赖数组位置
3. `initialState` 依赖首项
4. `maxEntries` 负值边界未处理
5. `exportJSON()` 静默吞掉 action 编码错误

### 6. API 和文档没有完全对齐新模型

包括：

1. `Dispatch` 命名与系统 `Dispatch` 模块冲突
2. Middleware 示例未完全对齐当前 async / actor 约束
3. 仓库内部测试仍保留旧的裸闭包类型注解

## 已完成的修复

### 并发与 actor 收口

1. `Reducer` 改为 `@MainActor`
2. `combineReducers` / `pullback` / `navigationReducer` 同步改为 `@MainActor`
3. `pullback` 的 `extract` 闭包同步收口到 `@MainActor`

### 异步与任务生命周期

1. 修复 `throttle` 的窗口判断
2. `runTask(id:)` 现在等待旧任务完成后再启动新任务
3. 直接取消返回的 `Task` 句柄时会清理内部任务表

### Store / ScopedStore 稳定性

1. observer 通知改为基于快照遍历
2. 失效 observer 在遍历中清理
3. `scope` 的状态来源不再通过 `fatalError` 掩盖生命周期边界

### Time Travel / Debug

1. 使用独立 `nextIndex`
2. `snapshot(at:)` 按逻辑 index 查询
3. `initialState` 独立保存
4. `maxEntries` 负值钳制并即时裁剪
5. `exportJSON()` 传播编码错误

### API / 文档 / 测试

1. `Dispatch` 重命名为 `ActionDispatcher`
2. Middleware 文档示例更新
3. 测试和 Demo reducer 声明统一回到 `Reducer<...>`
4. `CHANGELOG.md` 已更新

## 为什么这样修

### 1. 不是只补 workaround，而是修边界

如果只是给某些业务 reducer 手动补 `@MainActor`，问题仍然留在库层。

这次修复的方向是：

> 让库本身表达清楚它真实的运行模型，而不是把解释成本留给接入方。

### 2. 不是只让测试过，而是让语义成立

例如：

1. `throttle` 修的是“API 名实一致”
2. `runTask(id:)` 修的是“同 ID 任务替换语义”
3. time travel 修的是“调试坐标系稳定”

### 3. 不是只修代码，还修认知模型

这轮同时更新了 `CHANGELOG` 和严格并发迁移文档，就是为了把“这次到底修了什么、为什么要这么修”也沉淀下来。

## 本质问题是什么

这次所有问题往下归，核心其实是三件事：

### 1. 类型契约没有完全承认真实运行边界

这是 actor / 严格并发问题的根因。

### 2. 异步工具只覆盖了 happy path

这是 `throttle` 和 `runTask` 问题的根因。

### 3. debug / 生命周期逻辑默认边界永远理想

这是 time travel、observer、scope 稳定性问题的根因。

## 修复后的收益

1. Swift 6 严格并发下接入成本更低
2. MainActor 状态流模型更清晰
3. 异步原语更可信
4. 调试工具更稳定
5. 文档、测试和实现口径一致

## 当前状态

截至本轮修复：

1. 代码已完成修改
2. `swift build` 通过
3. `swift test` 通过
4. `CHANGELOG.md` 已更新
5. 严格并发收口分析已沉淀到 `Docs/STRICT_CONCURRENCY_MIGRATION.md`
