# TGReduxKit 架构与异步流处理分析

## 一、仓库概览

**TGReduxKit** 是一个专为 SwiftUI (iOS 17+) 设计的轻量级 Redux 状态管理框架。核心定位是：**比 TCA（The Composable Architecture）更轻，但比裸写 SwiftUI 状态管理更有纪律性**。

### 1.1 目录结构

```
Sources/TGReduxKit/
  Core/
    Store.swift            -- @MainActor @Observable 根 Store
    StoreType.swift        -- Store / ScopedStore 共享协议面
    ScopedStore.swift      -- Feature 级子 Store
    Middleware.swift       -- 中间件类型定义
    Reducer.swift          -- 纯函数 Reducer 类型
    CancellationID.swift   -- 轻量取消标识符
    DebugMiddleware.swift  -- 调试中间件（action log / state diff）
  Navigation/
    TGRoute.swift           -- 路由协议
    NavigationState.swift   -- 导航状态容器
    NavigationAction.swift  -- 导航 Action
    NavigationReducer.swift -- 导航 Reducer
  SwiftUI/
    Store+Binding.swift  -- 状态到 Binding 的桥接
    StoreProvider.swift  -- Environment 注入辅助

Sources/TGReduxKitNavigation/
  TGNavigationStack.swift -- 独立的 SwiftUI NavigationStack 适配层
```

### 1.2 核心类型定义

| 类型 | 角色 | 签名 |
|------|------|------|
| `Store<State, Action>` | 单一数据源，`@MainActor @Observable` | `class` |
| `ScopedStore<State, Action>` | Feature 级子 Store | `class` |
| `StoreType<State, Action>` | `Store` / `ScopedStore` 公共协议面 | `state` / `dispatch` / SwiftUI `binding`（异步原语仍为 root-only） |
| `Reducer<State, Action>` | 主 actor 上的纯函数，同步变换状态 | `@MainActor (inout State, Action) -> Void` |
| `ActionDispatcher<Action>` | 主线程 Action 派发 | `@MainActor (Action) -> Void` |
| `Middleware<State, Action>` | 副作用拦截器，同步签名 | `@MainActor (Store, Action, @escaping ActionDispatcher) -> Void` |
| `CancellationID` | 可取消任务标识符 | `Hashable, Sendable, ExpressibleByStringLiteral` |

---

## 二、核心架构：单向数据流

### 2.1 整体数据流

```
View (SwiftUI)
  │  dispatch(Action)
  ▼
Store (@MainActor @Observable)
  │
  ▼
Middleware Pipeline（洋葱模型，同步链式调用）
  │  在此拦截 Action
  │  可启动异步 Task
  │  异步完成后 dispatch 新 Action
  ▼
Reducer（纯函数, inout State）
  │  同步变换状态
  ▼
State 更新 → @Observable 通知 SwiftUI 重绘
  │
  ▼
ScopedStore 通过 WeakScopeObserver 级联刷新
```

### 2.2 Store：单一数据源

`Store<State, Action>` 是 `@MainActor @Observable` 的 class，保证：

- 所有状态读写、dispatch **统一收敛到主线程**
- 利用 Swift 5.9+/iOS 17+ 的 `@Observable` 宏自动驱动 SwiftUI 视图更新
- `state` 是 `private(set)`，外部只读不写，**唯一修改入口是 dispatch**

### 2.3 ScopedStore：Feature 级状态隔离

通过 `store.scope(state: KeyPath, action: transform)` 创建子 Store：

```swift
let catalogStore = store.scope(
    state: \.catalog,
    action: ShoppingAction.catalog
)
```

核心能力：

- **状态投影**：子 Store 只暴露 `KeyPath` 对应的局部状态，View 不需要知道根状态树结构
- **Action 自动映射**：子 Store 的 `dispatch(childAction)` 通过闭包包装为父级 Action
- **级联刷新**：根 Store 每次 reducer 执行后通知所有 ScopedStore 从根状态树重新读取 keyPath 对应值。由于值类型 copy-by-value 特性，只有实际变化时 `@Observable` 才会通知 View 更新
- **支持嵌套**：可以从 `ScopedStore` 继续 `.scope(...)` 向下派生更深层的子 Store

### 2.4 Middleware 洋葱模型

Middleware 采用经典的 Redux 洋葱模型（compose middleware）：

```swift
// Store.swift - dispatch 实现
public func dispatch(_ action: Action) {
    let initialDispatch: Dispatch<Action> = { [weak self] action in
        guard let self else { return }
        self.reducer(&self.state, action)      // 最内层：执行 reducer
        self.notifyChildObservers()            // 通知 ScopedStore 刷新
    }

    // 洋葱模型：reversed + reduce 将中间件串成链
    let dispatchFunction = middlewares.reversed().reduce(initialDispatch) { nextDispatch, middleware in
        { [weak self] action in
            guard let self else { return }
            middleware(self, action, nextDispatch)  // middleware 决定是否/何时调用 next
        }
    }

    dispatchFunction(action)
}
```

执行顺序：`middleware[0] 前置 → middleware[1] 前置 → reducer → middleware[1] 后置 → middleware[0] 后置`。这一行为已被测试验证。

---

## 三、异步流处理：核心解决方案

状态机中的异步流有 **四个核心难题**，TGReduxKit 分别给出了轻量级解法。

### 3.1 难题一：竞态条件（Race Condition）

**场景**：用户在搜索框快速输入 `"a"` → `"ab"` → `"abc"`，每次触发网络请求。如果 `"a"` 的请求最慢返回，它会覆盖 `"abc"` 的正确结果。

**解法：`runTask(id:)` — 同 ID 自动取消旧任务**

```swift
// Store.swift - 任务管理核心实现
@discardableResult
public func runTask(
    id: CancellationID? = nil,
    priority: TaskPriority? = nil,
    operation: @escaping @Sendable () async -> Void
) -> Task<Void, Never> {
    if let id {
        cancelTask(id: id)      // ← 先取消同 ID 的旧任务
    }

    let token = UUID()
    let task = Task(priority: priority) { [weak self] in
        await operation()

        guard let self, let id else { return }
        await self.finishTask(id: id, token: token)  // ← token 防止错位清理
    }

    if let id {
        managedTasks[id] = ManagedTask(token: token, task: task)
    }

    return task
}
```

Demo 中的搜索中间件应用：

```swift
// Middlewares.swift - 搜索去抖 + 竞态保护
public func makeProductSearchMiddleware(
    dependencies: ShoppingDependencies
) -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        next(action)

        guard case .catalog(.searchQueryChanged(let query)) = action else { return }
        guard !query.isEmpty else { return }

        let allProducts = store.state.catalog.allProducts

        store.runTask(id: "catalog-search") {
            // 防抖 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }  // 检查点 1

            let results = await dependencies.productSearchService.searchProducts(
                query: query, in: allProducts
            )

            guard !Task.isCancelled else { return }  // 检查点 2
            await store.dispatch(.catalog(.searchCompleted(query, results)))
        }
    }
}
```

**这套机制同时解决了三个问题**：

- **自动去抖（Debounce）**：300ms sleep 充当 debounce
- **取消竞态**：同 ID 新任务自动取消旧任务
- **防止过时响应**：网络返回后再次检查 Cancelled 状态

### 3.2 难题二：任务生命周期管理

**场景**：页面 A 发起 5 秒网络请求，用户 1 秒后离开页面。请求完成后 dispatch 到不存在的页面，轻则冗余更新，重则 crash。

**解法：三层防护**

**第一层 — `cancelAllTasks()`：页面离开时统一清理**

```swift
// Store.swift
public func cancelAllTasks() {
    let tasks = managedTasks.values.map(\.task)
    managedTasks.removeAll()
    tasks.forEach { $0.cancel() }
}
```

**第二层 — `weak self` 捕获：防止任务延长 Store 生命周期**

```swift
let task = Task(priority: priority) { [weak self] in
    await operation()
    // self 可能已经 deinit，不会 crash
}
```

**第三层 — Token 机制：防止任务清理错位**

```swift
// Store.swift
private struct ManagedTask {
    let token: UUID    // 唯一标识
    let task: Task<Void, Never>
}

private func finishTask(id: CancellationID, token: UUID) {
    // 只有 token 匹配（即"当前"任务）才会被清理
    guard let task = managedTasks[id], task.token == token else { return }
    managedTasks.removeValue(forKey: id)
}
```

Token 机制防止了以下场景的 bug：旧任务在 `cancelTask` 之后、新任务启动之前的瞬间完成，错误地移除了新任务在 `managedTasks` 中的记录。

### 3.3 难题三：线程安全与状态一致性

**场景**：Reducer 在主线程改状态的同时，后台网络回调 dispatch 新 action。两个操作交叠可能产生不一致的状态。

**解法：@MainActor 收敛 — 所有路径最终汇聚到主线程**

```swift
// Store 整体标注 @MainActor
@MainActor
@Observable
public final class Store<State, Action> {
```

三条约束保证一致性：

1. **Dispatch 是 @MainActor**：`public typealias Dispatch<Action> = @MainActor (Action) -> Void`
2. **Middleware 是 @MainActor**：拦截逻辑在主线程
3. **Reducer 在 dispatch 内同步执行**：状态变换相对于其他 dispatch 是原子的

异步回流的安全性由 Swift 并发自动保证：

```swift
// middleware 在后台线程启动的 Task 中调用
await store.dispatch(.someAction)
// Swift 并发自动将 @MainActor 函数调度到主线程执行
```

对比旧版（0.x）的问题：旧版使用 `NSLock + @unchecked Sendable` 混合并发模型，存在中间态风险。1.0 版本全面收敛到 `@MainActor`，消除了这类隐患。

### 3.4 难题四：Middleware 既是同步管道又是异步发起者

**这是 TGReduxKit 设计中最巧妙的地方。**

Middleware 的签名是**同步**的：

```swift
public typealias Middleware<State, Action> = @MainActor (
    Store<State, Action>,
    Action,
    @escaping Dispatch<Action>    // ← next 回调
) -> Void
```

但它处理异步流程的模式是 **"先 next，后异步"**：

```
dispatch(action)
  → middleware 拦截
    → next(action)  // 同步放行给 reducer，让 UI 立即响应
    → 如果匹配到异步 action
      → store.runTask(id:) {     // 异步启动
          await apiCall()
          store.dispatch(result)  // 异步完成后回流新 action
        }
```

关键设计原则：

- **Reducer 立即更新瞬态**：`isLoading = true` 通过 `next(action)` 同步到达 reducer
- **Middleware 不阻塞管道**：`next(action)` 总是先被调用
- **异步结果作为新 Action 回流**：形成了 `同步 dispatch → 异步执行 → 同步回流` 的循环

---

## 四、异步流处理的四层架构

```
┌──────────────────────────────────────────────────────────┐
│ Layer 1: Middleware 边界                                  │
│  "同步签名，异步内容" — 副作用与纯逻辑分离                   │
├──────────────────────────────────────────────────────────┤
│ Layer 2: CancellationID 任务管理                          │
│  同 ID 自动取消 → 解决竞态                                │
│  cancelAllTasks() → 解决生命周期                           │
│  Token 机制 → 防止任务清理错位                              │
├──────────────────────────────────────────────────────────┤
│ Layer 3: Swift Concurrency 结构化并发                      │
│  Task.isCancelled 双重检查点                              │
│  weak self 防止循环引用                                   │
│  @MainActor 自动线程调度                                  │
├──────────────────────────────────────────────────────────┤
│ Layer 4: @MainActor Store 状态一致性                       │
│  所有状态读写在主线程                                      │
│  dispatch 天然串行化                                      │
│  Observation 驱动 UI 更新                                 │
└──────────────────────────────────────────────────────────┘
```

---

## 五、异步操作的具体模式

### 5.1 模式一：基础 Task 模式（Fire-and-Forget）

```swift
let apiMiddleware: Middleware<AppState, AppAction> = { store, action, next in
    next(action)

    if case .fetchUser = action {
        Task {
            let user = await fetchUserFromAPI()
            await store.dispatch(.userLoaded(user))
        }
    }
}
```

特点：最简单，无取消能力。适用于不重复触发的场景。

### 5.2 模式二：托管任务模式（推荐）

```swift
store.runTask(id: "fetch-user") {
    let user = await api.fetchUser()
    guard !Task.isCancelled else { return }
    await store.dispatch(.userLoaded(user))
}
```

特点：自动取消同类任务 + `Task.isCancelled` 检查点。适用于搜索、列表刷新、表单提交等可重复触发的场景。

### 5.3 模式三：依赖注入 + Middleware 工厂

```swift
func makeUserMiddleware(
    dependencies: AppDependencies
) -> Middleware<AppState, AppAction> {
    { store, action, next in
        next(action)
        guard case .loadUser = action else { return }

        store.runTask(id: "load-user") {
            guard let user = try? await dependencies.userRepository.fetchUser() else {
                return
            }
            await store.dispatch(.userLoaded(user))
        }
    }
}
```

特点：依赖通过工厂函数注入，不侵入 Store。与外部 DI 容器（Factory、Swinject 等）兼容。

---

## 六、完整异步流程示例

以 Demo 中搜索功能为例：

```
用户输入 "iPhone"
       │
       ▼
TextField 通过 Binding 触发
catalogStore.dispatch(.searchQueryChanged("iPhone"))
       │
       ▼
rootStore.dispatch(.catalog(.searchQueryChanged("iPhone")))
       │
       ▼
Middleware Pipeline:
  1. loggingMiddleware: 打印 action
  2. analyticsMiddleware: 不匹配，跳过
  3. makeFeatureFlagMiddleware: 不匹配，跳过
  4. makeProductSearchMiddleware:
     - next(action) → reducer 更新 searchQuery = "iPhone", isSearching = true
     - 启动 runTask(id: "catalog-search")
       │
       ▼
异步 block:
  - await Task.sleep(300ms)          // 防抖
  - guard !Task.isCancelled           // 检查点 1
  - await service.searchProducts()    // 执行搜索
  - guard !Task.isCancelled           // 检查点 2
  - await store.dispatch(.searchCompleted("iPhone", results))
       │
       ▼
Middleware Pipeline 再次拦截 → 透传到 Reducer
       │
       ▼
Reducer (.searchCompleted):
  - guard query == currentSearchQuery  // 防止过时结果
  - 更新 visibleProducts, isSearching = false
       │
       ▼
ScopedStore 级联刷新 → @Observable 通知 SwiftUI 重绘
```

---

## 七、与其他方案的对比

| 维度 | TGReduxKit | TCA | Redux + Thunk |
|------|-----------|-----|---------------|
| 异步抽象 | Middleware + `runTask(id:)` | `Effect<Action>` 类型系统 | Thunk 函数 |
| 取消机制 | `CancellationID` + `cancelTask(id:)` | Effect 代数中的取消传播 | 手动管理 |
| 并发模型 | `@MainActor` 统一收敛 | `@MainActor` + `Effect.run` | 无约束 |
| 学习成本 | 低（用原生 Swift 并发） | 高（需理解 Effect 代数） | 中 |
| 依赖注入 | Middleware 工厂函数 | `@Dependency` 属性包装器 | 无内建方案 |
| 状态隔离 | `ScopedStore` + KeyPath | `Scope` reducer | 无内建方案 |
| UI 集成 | `@Observable` + Environment | `WithViewStore` | `connect()` |

---

## 八、设计哲学总结

### TGReduxKit 做了什么

- 用 Middleware 作为异步边界，将 Swift 原生结构化并发适配到 Redux 单向数据流
- 用 `CancellationID` 提供极薄的取消管理层，不引入新的异步抽象
- 用 `@MainActor` 统一线程模型，消除并发中间态
- 用 `ScopedStore` 实现 Feature 级状态隔离，不引入重型 reducer 协议

### TGReduxKit 刻意不做什么

- 不引入宏系统驱动 Reducer DSL
- 不建立完整的 `Effect<Action>` 类型系统和 Effect 代数
- 不内建依赖注入容器
- 不做时间旅行调试
- 不把导航做成第二套框架

### 核心设计智慧

> **用 Middleware 作为异步边界（同步管道包裹异步任务），用 CancellationID + Swift Task 管理任务生命周期，用 @MainActor 保证状态一致性，最终将复杂的异步流分解为"同步 dispatch → 异步执行 → 同步回流"的简单循环。**

TGReduxKit 的正确目标不是"简化版 TCA"，而是一个 **SwiftUI 原生、规则清晰、支持中型业务复杂度的轻量 Redux 框架**。它的异步处理方案通过 "Middleware + Task + CancellationID" 三件套，在不引入 Effect 重型抽象的前提下，有效解决了搜索去抖、任务取消、状态一致性等核心问题。

---

## 九、辨析：状态机模式能否视为 Redux 的起源？

### 9.1 问题的提出

在 iOS 开发中，我们经常用 Swift 的 `enum` 来建模有限状态机：

```swift
enum LoadingState {
    case idle
    case loading
    case loaded(Data)
    case failed(Error)
}
```

这种写法和 Redux 中的 `enum Action` + `struct State` 有强烈的形似感：

```swift
enum AppAction {
    case loadData
    case dataLoaded(Data)
    case loadFailed(Error)
}

struct AppState {
    var loadingState: LoadingState = .idle
}
```

两者都用 **枚举穷举可能的状态/事件**，都通过 **模式匹配分发到不同的处理分支**。这种相似性不是巧合——它指向一个更深层的问题：**Redux 的思想根源到底是什么？状态机模式在其中扮演了什么角色？**

### 9.2 追溯 Redux 的思想谱系

Redux 并非凭空出现。它的思想谱系可以画成一条清晰的演化链：

```
图灵机（1936）
  │  状态 + 转移规则 = 计算
  ▼
有限状态机（FSM, 1950s）
  │  状态集合 S + 转移函数 δ: (S, E) → S
  ▼
Elm Architecture（2012）
  │  Model → update(msg, model) → 新 Model
  │  view 根据 model 渲染
  ▼
Flux（Facebook, 2014）
  │  Dispatcher → Store → View
  │  Action 单向流动
  ▼
Redux（Dan Abramov, 2015）
  │  单一 Store + 纯函数 Reducer + Action
  │  Reducer = (State, Action) → State
  ▼
TCA（Point-Free, 2020）
  │  ReducerProtocol + Effect 代数 + Dependency
  ▼
TGReduxKit（2025）
    轻量 Redux + @Observable + CancellationID
```

这条演化链的关键节点是 **Elm Architecture**——它是第一个明确将"状态机"思想系统化地应用于 UI 架构的平台。Elm 的核心理念直接来自对有限状态机的函数式封装：

```
type Msg = Increment | Decrement | Reset
update : Msg -> Model -> Model
```

这本质上是**一个 `message → state → state` 的纯函数**，与状态机的转移函数 `δ: (S, E) → S` 完全同构。Redux 的作者 Dan Abramov 多次公开承认 Elm 是 Redux 的直接灵感来源。所以这条演化链不是推测，而是有明确溯源路径的事实。

### 9.3 状态机与 Redux 的同构关系

如果我们严格对比，Redux 的每个核心概念都能在状态机理论中找到精确对应：

| 状态机理论 | Redux / TGReduxKit |
|-----------|-------------------|
| 状态集合 `S` | `State` struct |
| 事件/输入符号 `E` | `Action` enum |
| 转移函数 `δ: (S, E) → S` | `Reducer: (inout State, Action) → Void` |
| 当前状态 `s ∈ S` | `Store.state` |
| 确定性转移（一个状态 + 一个事件 → 唯一的下一状态） | Reducer 是纯函数，同输入必得同输出 |
| 状态观察者 | `@Observable` 驱动的 View 层 |
| 转移副作用（Mealy 机） | Middleware |

更进一步，Redux 的 **单一数据源**（Single Source of Truth）原则恰好对应状态机"在任意时刻有且仅有一个活跃状态"的公理。**Action 作为状态的唯一变更入口**则对应"状态只能通过定义好的转移发生变迁"的约束。

所以答案很明确：**Redux 不仅受到状态机的影响——Redux 本质上就是一个带有副作用通道（Middleware）的确定性有限状态机的工程化实现。**

### 9.4 iOS 中 enum 的独特优势：Swift 的类型系统放大了这种相似感

为什么在 iOS/Swift 中，"状态机 → Redux"的类比感特别强？原因在于 Swift 的 `enum` 比大多数语言的枚举更强大：

**1. 关联值（Associated Values）让 Action 自然携带载荷**

```swift
enum CatalogAction: Equatable {
    case searchQueryChanged(String)           // 携带搜索文本
    case searchCompleted(String, [Product])   // 携带查询 + 结果
}
```

这恰好对应状态机中"事件携带参数"的需求——`δ(s, e_with_data)` 中的 `e_with_data` 被自然表达为 `case searchQueryChanged(String)`。而在 JavaScript 等语言中，你只能手动构造 `{ type: 'SEARCH_QUERY_CHANGED', payload: 'text' }` 这样松散的字典。

**2. 模式匹配（Pattern Matching）让 Reducer 读起来像状态转移表**

```swift
switch action {
case .loadRequested:          // 事件: 加载请求
    state.isLoading = true    // 转移: 进入加载态

case .loaded(let data):       // 事件: 加载完成（携带数据）
    state.isLoading = false   // 转移: 退出加载态
    state.data = data         // 转移: 写入数据

case .loadFailed(let error):  // 事件: 加载失败（携带错误）
    state.isLoading = false   // 转移: 退出加载态
    state.error = error       // 转移: 写入错误
}
```

这段代码就是一个 **状态转移表**——每一行是 `(当前条件, 触发事件) → 状态变更`。Swift 编译器的穷举检查保证了你不会遗漏任何 case，就像形式化验证中"转移必须对所有事件定义"的约束。

**3. 值类型 State（struct）天然保证转移前后的隔离**

```swift
struct ShoppingState: Equatable {
    var catalog: CatalogState
    var cart: CartState
    var isLoading: Bool
}
```

State 是值类型，Redux 的 `inout` 修改实际上是在同一块内存上做**原位变换**（而不是复制一份再替换）。这保证了转移前后状态的可比较性（`Equatable`），以及状态快照的廉价性——两点都对应状态机理论中的"可观测状态序列"需求。

### 9.5 但不能忽略 Redux 超越状态机的地方

尽管同构关系成立，Redux 在以下几方面确实超越了经典状态机模型：

| 经典 FSM | Redux |
|----------|-------|
| 状态数必须显式定义 | State struct 的字段组合自然形成隐式状态空间（可能极大） |
| 转移函数通常只关心当前状态 | Middleware 可以读取历史、访问外部世界 |
| 无并发概念 | `runTask(id:)` 管理异步任务的竞态与取消 |
| 状态通常是扁平的枚举 | 通过 `ScopedStore` 实现层级化状态组合 |
| 无组合性 | Reducer 可以任意组合（`combineReducers` 等） |
| 无副作用模型 | Middleware 洋葱模型是副作用的显式边界 |

简单来说，**Redux 是状态机从"封闭世界"走向"开放世界"的工程化扩展**：它保留了确定性转移的核心，但添加了组合性、层级化和受控的副作用通道。TGReduxKit 的 Middleware + CancellationID 模型，恰好是这种"受控副作用"最轻量的实现方式之一。

### 9.6 结论：从状态机视角理解 Redux 的价值

**把状态机视为 Redux 的起源不仅是合理的，而且在 Swift 的语境下具有极强的实践意义。**

这个视角带来的直接收益：

1. **设计 Action 时更严谨**：每个 `case` 是一个事件，问自己"这个事件在状态机上合法吗？"——如果状态机没有定义这个转移，那大概率不该有这个 Action。

2. **设计 State 时更收敛**：状态机一次只有一个状态，State struct 的字段组合也必须逻辑自洽——你不会同时 `isLoading = true` 且 `data = someData`（除非那是合法的中间态）。

3. **调试时多一条思考路径**：当出现诡异状态时，回到转移表视角："哪个事件序列导致了当前状态？这个序列在状态机中是合法的吗？"——这比从 View 层逐帧回溯高效得多。

4. **enum 不应该是"方便的类型工具"，而应该是"业务状态的形式化建模"**：在 Swift 中写 `enum AppAction`，你实际上是在定义这个 Feature 的**事件字母表**——状态机只接受字母表内的事件。

最后用一个类比来结束这段辨析：

> **状态机是 Redux 的"数学骨架"，而 Redux 是状态机在 UI 工程中的"肉身"。骨架决定了形状，肉身赋予了组合、并发和副作用处理的能力。TGReduxKit 做的事情，在最深的层次上，就是让这副骨架在 SwiftUI 的土壤里站得更稳。**

---

## 十、框架评分：TGReduxKit 多维评估

### 10.1 评分框架说明

以下评分从 **八个维度** 对 TGReduxKit（1.0 版本）进行评估。每个维度满分 10 分，评分基于对源码、文档、Demo 和测试的完整阅读。

评分的参照系是 **"同级别轻量状态管理框架"**，而非对标 TCA 或生产级基础设施。一个 8 分的轻量框架和一个 8 分的企业级框架，含金量不同——这里的分数反映的是 **"在它的定位下做得有多好"**。

### 10.2 分维评分

#### 维度一：架构设计（Architecture Design）— 8.5/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| 单向数据流完整性 | ★★★★★ | Store → Middleware → Reducer → State 链路清晰，没有短路或后门 |
| 关注点分离 | ★★★★★ | Reducer（纯逻辑）、Middleware（副作用）、View（渲染）三者边界分明 |
| 状态单一数据源 | ★★★★★ | `@MainActor @Observable` Store 严格保证唯一写入入口 |
| ScopedStore 设计 | ★★★★☆ | 投影 + 级联刷新机制优雅，但缺少 WritableKeyPath 双向绑定 |
| 洋葱模型执行顺序 | ★★★★★ | `reversed().reduce()` 的实现简洁且经测试验证 |

**核心优势**：架构骨架极简——核心类型只有 6 个，整个 Core 层代码量不到 400 行。在如此小的表面积内完成了 Redux 的单向数据流闭环，是优秀架构设计的体现。

**扣分点**：ScopedStore 目前只支持只读投影（KeyPath），不支持 WritableKeyPath 双向写入。如果子模块需要直接修改父状态中的某个字段，目前只能绕道 Action，略显不便。Navigation 模块与 Core 的耦合方式可以更清晰。

#### 维度二：API 设计与开发体验（API Design & DX）— 8/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| 上手难度 | ★★★★★ | 从零到第一个可用 Store 只需 4 步，5 分钟 |
| API 表面积 | ★★★★★ | 6 个核心类型 + 3 个扩展方法，API 数量极克制 |
| SwiftUI 集成自然度 | ★★★★★ | `@Observable` + Environment + Binding 桥接，完全是原生写法 |
| 类型安全 | ★★★★★ | 泛型 `<State, Action>` 全程编译器检查，无 Any/eraseToAny 模式 |
| 错误提示友好度 | ★★★☆☆ | 编译错误在嵌套 Action 模式下可能较长，缺少自定义错误诊断 |
| 代码补全体验 | ★★★★☆ | 枚举驱动的 Action 配合 switch 自动补全，体验好；但 KeyPath 推导偶尔需要显式类型标注 |

**亮点示例**：

```swift
// 从定义到使用的完整闭环，每一步都有编译器护航
let store = Store(initialState: AppState(), reducer: appReducer)  // 1 行
store.dispatch(.increment)                                         // 类型安全
Text("Count: \(store.state.count)")                               // Observable 自动更新
TextField("", text: store.binding(get: \.name, send: AppAction.updateName))  // 原生 Binding
```

**扣分点**：当 Action 嵌套层级较深时（如 `.catalog(.searchCompleted(query, results))`），编译错误可能拉得很长，缺乏定制化的错误诊断信息。这属于 Swift 泛型的固有问题，但框架可以提供 `typealias` 或辅助宏来缓解。

#### 维度三：异步流处理（Async Flow Handling）— 7.5/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| 竞态消除 | ★★★★☆ | `runTask(id:)` 同 ID 取消机制有效，双重 `Task.isCancelled` 检查模式成熟 |
| 任务生命周期 | ★★★★☆ | 三层防护（cancelAll + weak self + Token）覆盖主要场景 |
| 去抖/节流 | ★★★☆☆ | 依赖手动 `Task.sleep` 实现，缺少声明式 API |
| 异步错误处理 | ★★★☆☆ | 错误由业务自行 catch，框架不提供统一的错误回流通道 |
| 复杂异步编排 | ★★☆☆☆ | 不支持链式 Effect、并行合并、超时重试等高级模式 |

**核心优势**：在不用 Effect 类型系统的情况下，用 `CancellationID` + `runTask` 极薄地覆盖了最常见的三种异步场景（搜索去抖、列表刷新、表单提交）。Swift 原生并发的 `Task.isCancelled` 协作式取消比 TCA 的 `Effect.cancel(id:)` 更符合 Swift 生态的直觉。

**扣分点**：
- 缺少声明式去抖/节流支持——当前靠 `Task.sleep(300ms)` 手写，容易忘或写错
- 无内置的重试、超时、并行合并等原语——复杂异步编排需要业务方自己实现
- 异步错误统一处理缺失——每个 middleware 各自 catch，没有统一的 `errorAction` 回流通道
- 不提供 TestStore 的 `receive` 类断言来验证异步 Action 序列

**与 TCA 对比**：TCA 的 `Effect` 类型系统在这一个维度上确实更强——它可以表达 `debounce → network → retry(3) → timeout(10s)` 这样的链式效应。TGReduxKit 选择了不做这些，换取更轻的学习成本。在这个定位下这个分数是合理的——它不是"做不到"，而是"选择不做"。

#### 维度四：并发安全（Concurrency Safety）— 8/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| 线程模型清晰度 | ★★★★★ | `@MainActor` 统一收敛，无歧义 |
| 并发正确性保证 | ★★★★☆ | Swift 编译器的 Sendable 检查 + MainActor 静态度量覆盖主要路径 |
| 锁策略 | ★★★★★ | 无锁设计——利用 MainActor 串行化替代 NSLock |
| Sendable 合规性 | ★★★★☆ | State/Action 强制 Equatable + Sendable，Task 闭包标注 @Sendable |
| 低版本兼容风险 | ★★★★☆ | @Observable 强依赖 iOS 17+，无法向下兼容 |

**关键变迁**：1.0 版本放弃了 0.x 的 `NSLock + @unchecked Sendable` 中态方案，全面迁移到 `@MainActor`。这是一个正确的收敛——与其在"能跑但不安全"和"线程安全但复杂"之间摇摆，不如一刀切地选一个简单可靠的策略。

**扣分点**：
- 对于 CPU 密集型的 reducer（如大量数据处理），全部跑在主线程可能造成 UI 卡顿——但目前没有提供 `backgroundReducer` 之类的卸载机制
- iOS 17+ 的硬性要求限制了下游项目的适用范围

#### 维度五：可组合性与可扩展性（Composability & Extensibility）— 7/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| 状态组合 | ★★★★☆ | struct 嵌套 + KeyPath scope 自然支持层级状态 |
| Reducer 组合 | ★★★★☆ | 通过子 Reducer 调用实现，语义清晰 |
| Middleware 组合 | ★★★★☆ | 洋葱模型天然支持，数组顺序即执行顺序 |
| 跨 Feature 通信 | ★★★☆☆ | 只能通过父级 Action 转发，无发布-订阅机制 |
| 外部扩展点 | ★★★★☆ | Middleware 工厂 + DI 协议注入，不锁定容器选择 |
| 大项目可维护性 | ★★★☆☆ | 缺乏模块边界的强制机制，完全依赖团队纪律 |

**核心优势**：`scope()` 的嵌套能力和 ScopedStore 的递归刷新机制设计得很干净。Demo 中展示的三层嵌套（`ShoppingState → CartState/CatalogState/FeatureFlagsState`）是中型项目的典型模式，工作良好。

**扣分点**：
- 缺少跨 Feature 的松耦合通信机制。如果 Feature A 需要响应 Feature B 的状态变化，当前只能通过根 Store 在 reducer 中联动，或者把所有逻辑上提到父级 reducer——这会破坏 Feature 的自治性
- 没有"模块注册"或"Feature 发现"等大型项目的组织模式——状态树变深后，`AppAction` 枚举会成为巨型文件

#### 维度六：可测试性（Testability）— 6.5/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| Reducer 纯函数测试 | ★★★★★ | `inout State` 语义让 reducer 测试极其简单 |
| Middleware 行为测试 | ★★★★☆ | 测试中展示了 middleware 链式调用验证 |
| 异步 Action 测试 | ★★★☆☆ | 靠 `Task.sleep` 等待，无时间控制/加速机制 |
| TestStore | ★☆☆☆☆ | 不存在 TestStore，缺少 action 序列断言工具 |
| 依赖替换测试 | ★★★☆☆ | 通过工厂函数注入 mock 可行，但无内建辅助工具 |

**实际情况**：当前测试文件 `TGReduxKitTests.swift` 覆盖了 Store 初始化、dispatch、middleware 链、scoped store 同步、嵌套 scope、任务取消、debug middleware 7 个方面。覆盖质量不错，但缺少：
- TestStore（或等价工具）来断言"给定一个 action 序列，期望得到的状态序列"
- 异步任务的时间控制（如 TCA 的 `TestStore` 使用 `Clock` 协议加速时间流逝）
- Middleware 单元测试的独立 harness

**扣分点**：TestStore 的缺失是当前框架最大的功能空白之一。在没有 TestStore 的情况下，测试一个完整异步流程（如"派发搜索 → 等待去抖 → 断言搜索结果 → 断言 loading 结束"）需要手写 `Task.sleep`，导致测试变慢且不稳定。

#### 维度七：文档与生态（Documentation & Ecosystem）— 7/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| README 完整性 | ★★★★☆ | 包含快速开始、高级用法、最佳实践，覆盖主要场景 |
| 架构文档 | ★★★★☆ | `ARCHITECTURE.md` 清晰定义了设计原则和模块职责 |
| Demo 质量 | ★★★★★ | 三个 Feature + Feature Flag 集成 + Deep Link 的完整示例 |
| API 文档注释 | ★★★★☆ | 核心类型和公开方法有 DocC 注释 |
| 错误处理指导 | ★★☆☆☆ | 缺少错误处理模式的最佳实践文档 |
| 社区 & 生态 | ★☆☆☆☆ | 单仓库项目，无社区贡献、插件或第三方中间件 |

**亮点**：`TGReduxKitDemo` 是一个质量很高的示例——它不仅展示了"怎么用"，还展示了"怎么设计"。三个 ScopedStore 的注入、Feature Flag 的两层边界、Deep Link 的统一解析，都是真实的工程决策，不是玩具代码。

**扣分点**：
- 缺少专门的"从 UIKit/Combine 迁移指南"
- 错误处理、重试策略、乐观更新等中高级模式没有文档沉淀
- 作为一个独立开源项目，没有 issue 模板、PR 模板、CI 配置等社区基础设施

#### 维度八：生产就绪度（Production Readiness）— 6/10

| 评估点 | 得分 | 说明 |
|--------|------|------|
| 核心稳定性 | ★★★★☆ | 并发模型已收敛，API 已稳定 |
| 边界情况覆盖 | ★★★☆☆ | 缺少对极端场景（大量 Action 洪流、内存压力下的 Task 行为）的验证 |
| 性能 | ★★★★☆ | 无锁设计 + Observation 的细粒度更新，性能基线好 |
| 错误恢复 | ★★☆☆☆ | 无可观测的状态快照/回滚机制 |
| 线上可观测性 | ★★★☆☆ | debug middleware 可用，但缺少结构化的 action 时间线或性能 trace |
| 版本策略 | ★★★★☆ | 有 CHANGELOG.md，版本号使用了语义化版本 |

**扣分点**：
- 缺乏正式的线上监控手段——debug middleware 是 `print` 级别的，不适合生产环境的 issue 回溯
- 没有状态迁移或回滚能力——如果某个 action 导致非法状态，没有内建的恢复路径
- 未在公开渠道披露过已被哪些项目采用、承载过多少用户——这降低了外部团队采用时的信心

### 10.3 综合评分

```
维度                      权重    得分    加权
────────────────────────────────────────────
架构设计                   20%    8.5    1.70
API 设计与开发体验          20%    8.0    1.60
异步流处理                  20%    7.5    1.50
并发安全                   15%    8.0    1.20
可组合性与可扩展性          10%    7.0    0.70
可测试性                    5%    6.5    0.33
文档与生态                   5%    7.0    0.35
生产就绪度                   5%    6.0    0.30
────────────────────────────────────────────
加权总分                         7.68 / 10
```

**权重说明**：异步流处理、架构设计和 API 体验被赋予了更高的权重，因为这三点是 TGReduxKit 定位的核心——"轻量 Redux + SwiftUI 原生异步处理"。可测试性和生产就绪度权重较低，因为它们更多是"锦上添花"而非框架的核心竞争力。

### 10.4 横向对比参考

以下对比不是要分个高下，而是帮助判断**什么场景选什么工具**：

| 维度 | TGReduxKit | TCA | 原生 SwiftUI |
|------|-----------|-----|-------------|
| 学习曲线 | ★★★★★ 极低 | ★★☆☆☆ 陡峭 | ★★★★★ 极低 |
| 小项目适用性 | 略重 | 过重 | ★★★★★ 最佳 |
| 中型项目适用性 | ★★★★★ 最佳 | 可用但偏重 | 状态管理开始失控 |
| 大型项目适用性 | 团队纪律要求高 | ★★★★★ 最佳 | 不适用 |
| 异步处理能力 | 够用（3 种模式） | 强大（Effect 代数） | 基础（.task） |
| 测试基础设施 | 基础 | 成熟（TestStore + Clock） | 需自行搭建 |
| 架构约束力 | 中等（靠团队纪律） | 强（框架级约束） | 弱（无约束） |
| 团队上手时间 | 半天 | 1-2 周 | 即用 |
| 迁移成本（从 SwiftUI） | 低 | 高 | — |
| 框架本体代码量 | ~600 行 | 数万行 | 不适用 |

### 10.5 适用场景判断

**强烈推荐 TGReduxKit 的场景**：

- 3-8 个 Feature 模块的中型 SwiftUI 应用
- 团队希望引入单向数据流但不想投入 TCA 的学习成本
- 需要状态管理有明确纪律，但不要求框架级强约束
- 应用以网络请求 + 本地状态为主，异步模式集中在"请求-响应"类

**可以考虑但需要补课的场景**：

- 10+ Feature 模块的大型应用 → 需要团队额外建立模块边界规范
- 复杂的异步编排（链式请求、并行合并、轮询、WebSocket）→ 需要自行封装或引入辅助库
- 对测试覆盖率有极高要求的项目 → 在没有 TestStore 的情况下需要额外投入测试基础设施

**不推荐 TGReduxKit 的场景**：

- 需要支持 iOS 16 及以下的项目 → @Observable 不兼容
- 对时间旅行调试有强需求的项目 → 框架未设计此能力
- 只有 1-2 个简单页面的应用 → 裸 SwiftUI `@State` + `@Environment` 更合适

### 10.6 评分总评

> **TGReduxKit 是一个定位精准、骨架干净的轻量 Redux 框架。综合得分 7.7/10，在它所定位的"比 TCA 轻、比裸 SwiftUI 有纪律"的赛道上表现出色。最大的价值不在于它解决了多少复杂问题，而在于它清晰地划出了"什么该做、什么不该做"的边界——这是一种难得的工程克制。**
>
> **最值得改进的三个方向**：补齐 TestStore（一次性拉升可测试性得分）、增加声明式去抖/重试 API（拉升异步处理得分）、建立错误处理与状态恢复的规范路径（拉升生产就绪度得分）。这三项的边际收益远超其实现成本。
