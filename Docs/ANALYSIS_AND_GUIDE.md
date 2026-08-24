# TGReduxKit 分析、对比与轻量化改进指导

## 1. 文档目标

本文档解决五件事：

1. 说明 TGReduxKit 当前源码的真实能力边界
2. 判断它是否适合继续作为一个“比 TCA 轻”的状态管理框架
3. 分析哪些能力可以增强，哪些能力不应该照搬 TCA
4. 给出一套可落地的分阶段改进方案
5. 给出在 Livis 一类 SwiftUI 项目中的使用与演进规范

本文档以当前仓库源码为准，不以口头约定、历史印象或理想设计为准。

---

## 2. 当前源码基线

### 2.1 核心类型

当前源码中的核心定义是：

```swift
public typealias Reducer<State, Action> = @MainActor (inout State, Action) -> Void
public typealias ActionDispatcher<Action> = @MainActor (Action) -> Void
public typealias Middleware<State, Action> = @MainActor (Store<State, Action>, Action, @escaping ActionDispatcher<Action>) -> Void
```

直接结论：

- Reducer 是收口到 `@MainActor` 的 `inout` 变异模型
- Middleware 是 `@MainActor` 上的同步函数签名
- 异步副作用依赖 middleware 内部手动启动 `Task`
- Store 基于 `@Observable` 驱动 SwiftUI 刷新
- `StoreType` 已统一 `Store` / `ScopedStore` 的基础 SwiftUI API 面

### 2.2 Store 执行模型

当前 `Store` 的核心行为可以概括为：

```swift
@Observable
public final class Store<State, Action>: @unchecked Sendable {
    public private(set) var state: State
    private let reducer: Reducer<State, Action>
    private let middlewares: [Middleware<State, Action>]
    private let lock = NSLock()

    public func dispatch(_ action: Action) {
        let initialDispatch: Dispatch<Action> = { action in
            self.lock.lock()
            defer { self.lock.unlock() }
            self.reducer(&self.state, action)
        }

        let dispatchFunction = middlewares.reversed().reduce(initialDispatch) { next, middleware in
            { action in
                middleware(self, action, next)
            }
        }

        dispatchFunction(action)
    }
}
```

这意味着：

- Action 先进入 middleware 链
- middleware 可以决定是否调用 `next(action)`
- reducer 在锁内同步修改 state
- Observation 负责 UI 变更传播
- Store 当前用 `@unchecked Sendable` 放宽了编译器并发检查

### 2.3 SwiftUI 集成能力

当前库已经具备两个对 SwiftUI 很有价值的轻量能力：

#### 环境注入

```swift
ContentView()
    .provideStore(store)
```

#### Binding 桥接

```swift
TextField(
    "Name",
    text: store.binding(
        get: \.name,
        send: { .updateName($0) }
    )
)
```

这两个能力说明 TGReduxKit 的方向不是“完全通用状态容器”，而是“为 SwiftUI 场景优化的轻量单向数据流框架”。

### 2.4 Navigation 支持

当前库包含：

- `TGRoute`
- `NavigationState<Route>`
- `NavigationAction<Route>`
- `navigationReducer`
- `TGNavigationStack`（位于独立 target `TGReduxKitNavigation`）

这说明作者已经把“导航状态化”纳入框架边界。

---

## 3. 当前框架的真实优势

### 3.1 它确实比 TCA 轻

TGReduxKit 当前的优势不在“能力最全”，而在“足够轻”：

- API 面积小
- 学习成本低
- 不依赖宏系统和依赖注入体系
- 没有复杂 effect algebra
- 对 SwiftUI Observation 的适配非常自然

如果团队目标是：

- 希望有明确状态流
- 不想把工程复杂度拉到 TCA 水平
- 可以接受通过约束和模板补齐纪律

那么 TGReduxKit 的定位是合理的。

### 3.2 它更贴近 SwiftUI 原生开发习惯

与 TCA 相比，TGReduxKit 不要求开发者同时接受一整套：

- ReducerProtocol
- Effect 生命周期建模
- Dependency 注入系统
- TestStore 推演模型
- Navigation 状态 DSL

它保留了更接近原生 Swift 的写法：

- `struct State`
- `enum Action`
- `inout reducer`
- SwiftUI `Binding`
- Environment 注入

这让它更适合中小型项目或希望逐步引入架构纪律的团队。

### 3.3 它已经具备进一步增强的基础

当前框架虽然简单，但不是死路：

- Store 已经承担统一 dispatch 入口
- middleware 已经是副作用总线
- reducer 已经是状态变换中心
- navigation 已经开始状态化

这意味着它可以继续增强，而且不必直接演变成 TCA。

---

## 4. 当前主要问题

### 4.1 文档与实现不一致

这是当前最严重的问题。

例如 `ARCHITECTURE.md` 中写到：

- Reducer 可以返回新 State
- Middleware 计划基于 `async/await`

但真实实现并不是这样。

这会带来两个直接后果：

- 使用者会按错误 API 设计业务
- 团队无法建立稳定的框架认知

结论：

- 当前 TGReduxKit 最大问题不是“太弱”
- 而是“认知边界不稳定”

### 4.2 没有 scoped store

当前只有根 `Store<State, Action>`，没有官方子 Store 能力。

后果：

- View 容易直接访问根状态树
- Feature 边界容易失真
- 子模块被迫知道父级状态结构
- 状态树一旦变深，页面代码会快速耦合

这类问题在业务复杂度增加后会放大得非常快。

### 4.3 副作用系统过于原始

当前副作用系统的核心模式是：

- middleware 拦截 action
- 手动启动 `Task`
- 异步完成后再次 dispatch action

这个模式可用，但缺少以下关键能力：

- 取消同类旧任务
- 去抖与节流
- 长生命周期任务管理
- 可测试的异步调度
- 更稳定的任务归属关系

### 4.4 并发模型处于中间态

当前 Store 使用：

```swift
public final class Store<State, Action>: @unchecked Sendable
```

同时只对 reducer 写入做了 `NSLock` 保护。

这意味着它不是一个彻底的 MainActor Store，也不是一个严格定义读写隔离的并发 Store。

风险包括：

- `state` 读取策略没有清晰边界
- middleware 可以从任意任务回流 dispatch
- Observation 与跨线程访问的配合没有被正式定义

这类设计在简单项目中通常“能跑”，但在大型项目里最容易制造偶发性问题。

### 4.5 测试与调试基础设施不足

当前缺失：

- TestStore
- middleware test harness
- action timeline
- state diff
- reducer transition assertion

这不是“高级附加项”，而是框架可持续演进的基础设施。

### 4.6 导航还只是基础层

当前导航能力能覆盖：

- push
- pop
- popToRoot
- sheet
- fullScreenCover

但还没有系统解决：

- deep link 统一路由解析
- 跨 feature 导航编排
- route guard
- nested coordinator
- modal result 反馈

因此当前导航能力适合基础项目，不适合复杂多流转应用。

---

## 5. 关键判断：能不能按这个文档继续改进

结论：可以，而且值得继续改进。

但前提不是“向 TCA 靠齐”，而是“做轻量增强版 TGReduxKit”。

### 5.1 可以改进的原因

TGReduxKit 已经有了单向数据流最核心的三根支柱：

1. 统一 Store
2. 可组合 reducer
3. 可拦截的 middleware

只要在这些基础上做有边界的增强，就能显著提升可维护性，而不会丢失轻量优势。

### 5.2 不应该照搬 TCA 的部分

如果目标是“比 TCA 轻”，就不应该一次性引入以下内容：

- 宏驱动 reducer DSL
- 完整 dependency 容器体系
- 全量 effect 类型系统
- 时间旅行调试
- 复杂的导航 DSL
- 强框架化的 feature protocol 层级

这些能力当然强，但它们正是 TCA 心智负担变高的原因之一。

### 5.3 应该优先补齐的部分

应优先引入那些“收益高、认知增量小”的能力：

- 文档与实现统一
- MainActor 并发模型
- scoped store
- 轻量 cancellation
- TestStore
- Debug middleware

这几项增强是最划算的，因为它们几乎不会改变现有开发者的使用方式，但能明显提升框架稳定性。

---

## 6. 轻量增强版设计原则

如果要把 TGReduxKit 继续做下去，建议遵守以下原则。

### 原则 1：保留当前 reducer 语义

继续使用：

```swift
(inout State, Action) -> Void
```

原因：

- 性能直观
- 语义简单
- 易于被普通 Swift 开发者接受
- 不必引入返回式 reducer 和额外包装层

### 原则 2：Store 采用 MainActor 策略

建议收敛到：

- `Store` 整体运行在 `@MainActor`
- state 读写与 dispatch 统一主线程
- middleware 内异步任务回流时显式回到主线程

原因：

- 与 SwiftUI/Observation 心智一致
- 比彻底线程安全 Store 更轻
- 可以移除 `@unchecked Sendable` 这类高风险声明

这是当前最值得做的收敛方向。

### 原则 3：新增 scoped store，但不要做过度抽象

建议目标 API：

```swift
let childStore = store.scope(
    state: \.profile,
    action: AppAction.profile
)
```

设计目标：

- 让子 View 只看到自己的状态和 action
- 不要求引入全新的 reducer protocol
- 不要求额外的 effect 系统

这项能力是“轻量框架进入可维护状态”的关键分水岭。

### 原则 4：副作用只做轻量 task 管理

不要一开始设计完整 Effect 类型系统。

先解决三个核心问题：

1. 同类任务取消
2. 页面离开后的任务收敛
3. 去抖与节流

可以考虑引入的最小抽象是：

- `CancellationID`
- `TaskRegistry`
- `dispatchAsync` 或 middleware helper

目标是控制异步任务，而不是复制 TCA 的完整 Effect 世界。

### 原则 5：测试优先补基础断言，不追求过度模拟

优先提供：

- action 发送
- state 断言
- middleware 结果断言

而不是一步到位做复杂测试运行时。

### 原则 6：Debug 能力以 middleware 为中心

最轻量的调试增强方式不是 DevTools，而是提供一组可选 middleware：

- action logger
- state diff logger
- performance logger
- navigation logger

这样可以保持零侵入，同时对日常排障足够有用。

---

## 7. 推荐的改进内容

### 7.1 P0：统一文档与源码

这是第一优先级。

必须修正：

- `README.md` 对 reducer 和 middleware 的描述
- `ARCHITECTURE.md` 中与真实实现不符的设计表述
- Demo 对导航、环境注入和 middleware 用法的说明

收益：

- 消除认知漂移
- 降低错误使用概率
- 为后续所有改进建立稳定基线

### 7.2 P1：收紧并发模型

建议采用唯一明确策略：

#### 推荐策略：MainActor Store

- `Store` 标注 `@MainActor`
- `dispatch` 标注 `@MainActor`
- `state` 读取保证主线程一致性
- middleware 异步回流统一通过主线程调度

不建议继续维持当前状态：

- `NSLock` + `@unchecked Sendable` + Observation 混合并发

因为这种中间态最难维护。

### 7.3 P1：增加 scoped store

建议新增：

```swift
func scope<ChildState, ChildAction>(
    state: KeyPath<State, ChildState>,
    action: @escaping (ChildAction) -> Action
) -> Store<ChildState, ChildAction>
```

如果后续需要子状态双向写入，再考虑扩展：

```swift
WritableKeyPath<State, ChildState>
```

收益：

- View 只依赖局部状态
- Feature 更容易模块化
- 父子模块边界更清晰
- 组件复用能力增强

### 7.4 P1：增加轻量取消机制

建议不要直接设计 `Effect<Action>`。

先做更小的抽象：

```swift
struct CancellationID: Hashable, Sendable
```

围绕它建立：

- 启动任务
- 取消同 ID 任务
- 页面离开时统一取消

优先覆盖场景：

- 搜索请求去抖
- 列表刷新覆盖旧请求
- 页面退出取消未完成任务

### 7.5 P2：增加 TestStore

建议目标不是复刻 TCA 的完整测试模型，而是提供最小够用能力：

- 初始化测试状态
- 发送 action
- 断言状态变化
- 等待 middleware 回流 action

这已经足以覆盖大多数业务 reducer 测试。

### 7.6 P2：增加 Debug 工具

建议先提供一组官方 middleware：

- `loggingMiddleware`
- `stateDiffMiddleware`
- `actionTimelineMiddleware`
- `navigationDebugMiddleware`

这些能力的价值非常高，因为它们几乎不改变现有 API，却能显著改善定位问题的效率。

### 7.7 P3：增强导航能力

导航建议继续保持轻量，不要强行造完整 coordinator 框架。

优先增强：

- deep link 统一解析入口
- route guard
- 跨模块导航约束

暂不优先：

- typed modal result DSL
- 多层 coordinator 抽象
- 全局导航脚本化系统

---

## 8. 不建议做的“伪进步”

为了保持比 TCA 轻，以下方向应当避免：

### 8.1 不要为了“先进”而引入宏系统

宏能减少样板代码，但会明显提升框架理解门槛。

对于 TGReduxKit 这种定位，更重要的是：

- 可读
- 可调试
- 可快速上手

### 8.2 不要过早引入完整依赖注入体系

TCA 的 dependency 系统非常强，但也带来一套新的学习成本。

TGReduxKit 更合适的方式是：

- 业务依赖继续放在应用层
- middleware 注入服务
- 测试时做局部替换

### 8.3 不要把 navigation 做成第二套框架

导航应该继续保持“状态容器 + 少量适配能力”的定位。

一旦导航层过度 DSL 化，就会让整个框架从轻量工具演变为重型架构系统。

### 8.4 不要一步到位追求全量 effect system

真正昂贵的不是写出一个 `Effect` 类型，而是：

- 生命周期定义
- 取消传播
- 测试调度
- 组合规则
- 依赖注入

这条路一旦走深，最终会自然滑向 TCA。

---

## 9. 与 TCA 的合理边界

### 9.1 TGReduxKit 应该学 TCA 什么

应该学习的是：

- Feature 边界清晰
- 副作用要可控
- 测试必须可验证
- 导航应该状态化
- 复杂项目需要工具链

### 9.2 TGReduxKit 不该学 TCA 什么

不该直接复制的是：

- 全量抽象层级
- 强框架化 reducer DSL
- 重 dependency runtime
- 过于完整的 effect 代数模型

### 9.3 正确目标

TGReduxKit 的正确目标不是：

- 成为一个简化版 TCA

而是：

- 成为一个 SwiftUI 原生、规则清晰、支持中型业务复杂度的轻量 Redux 框架

---

## 10. Livis 场景下的使用规范

### 10.1 新功能模块的正确开发顺序

每个新功能模块按以下顺序落地：

1. 定义 `FeatureState`
2. 定义 `FeatureAction`
3. 实现 `featureReducer`
4. 接入 `AppState`
5. 接入 `AppAction`
6. 接入根 reducer
7. 补齐 middleware
8. 最后实现 View

禁止反向开发：

- 先写 View 再猜状态结构
- 先写 dispatch 再补 action
- 先在页面里堆业务逻辑

### 10.2 State 边界规范

根状态只承担聚合职责：

```swift
struct AppState {
    var navigation: NavigationState<AppRoute>
    var user: UserState
    var settings: SettingsState
    var featureA: FeatureAState
    var featureB: FeatureBState
}
```

原则：

- 根状态只聚合
- Feature 细节放在各自子状态
- View 只读自己作用域内的状态

### 10.3 Action 设计规范

Action 描述“发生了什么”，不要描述“打算怎么做”。

推荐：

```swift
case loadItems
case itemsLoaded([Item])
case itemsLoadFailed(String)
```

避免：

```swift
case callItemsAPI
case performRefreshFlow
```

### 10.4 Reducer 设计规范

Reducer 只负责状态变换：

```swift
private let featureReducer: Reducer<FeatureState, FeatureAction> = { state, action in
    switch action {
    case .loadItems:
        state.isLoading = true
        state.error = nil
    case .itemsLoaded(let items):
        state.isLoading = false
        state.items = items
    case .itemsLoadFailed(let error):
        state.isLoading = false
        state.error = error
    }
}
```

Reducer 内禁止：

- 网络请求
- 文件读写
- 权限调用
- 启动任务
- 日志埋点

### 10.5 Middleware 设计规范

Middleware 负责：

- API 请求
- 权限处理
- 日志与埋点
- 导航副作用
- 异步回流 action

建议模式：

```swift
let middleware: Middleware<AppState, AppAction> = { store, action, next in
    next(action)

    if case .feature(.loadItems) = action {
        Task {
            let items = await repository.loadItems()
            await MainActor.run {
                store.dispatch(.feature(.itemsLoaded(items)))
            }
        }
    }
}
```

### 10.6 SwiftUI View 设计规范

View 只做三件事：

1. 读取状态
2. 派发 action
3. 组合 UI

推荐：

```swift
Toggle(
    "Dark Mode",
    isOn: store.binding(
        get: \.isDarkMode,
        send: FeatureAction.toggleDarkMode
    )
)
```

避免：

- 在 View 中拼业务状态转换
- 在多个页面复制相同状态逻辑
- 直接跨 feature 访问深层状态

---

## 11. 模块化改进计划与预计投入

目标是做“轻量增强”，不是“大重构”。

| 模块 | 目标 | 建议动作 | 预计投入 |
|------|------|----------|----------|
| Documentation | 统一认知 | 修正 README、ARCHITECTURE、Demo 描述与示例 | 0.5 天 |
| Core / Store | 收紧并发 | 切换为 MainActor Store，清理 `@unchecked Sendable` 中间态 | 1 天 |
| SwiftUI Integration | 降低耦合 | 增加 scoped store 与 feature 级 Binding 能力 | 1 天 |
| Core / Middleware | 控制副作用 | 增加 cancellation、debounce、任务注册基础设施 | 1.5 天 |
| Testing | 提高可验证性 | 建立 TestStore、middleware test helper、状态断言工具 | 1 天 |
| Debugging | 提高排障效率 | 提供 action log、state diff、navigation log | 0.5 天 |
| Navigation | 提升实战性 | 补 deep link 入口与 route guard 约束 | 1 天 |
| Livis App Layer | 统一接入方式 | 给出 feature 模板、接入顺序和边界规范 | 0.5 天 |

总投入约为 7 天。

这个投入远低于迁移到 TCA 或自建重型架构体系的整体成本。

---

## 12. 旧设计的问题与重构收益

### 12.1 旧设计的问题

当前主要问题不是某一个 API 不够强，而是整体处于“可用但未收敛”的状态：

- 文档和源码边界不一致
- 并发模型没有完全定型
- Feature 边界主要靠团队自觉
- 异步副作用缺乏统一约束
- 测试与调试设施偏弱

### 12.2 改进后的收益

如果按本文档推进，预期收益是：

- 保留轻量心智
- 提升模块边界清晰度
- 降低跨页面耦合
- 降低异步回流错误
- 提高测试与排障效率
- 让 TGReduxKit 能承接中型复杂度项目

### 12.3 为什么这种方案比直接上 TCA 更合适

因为当前问题的本质不是“缺一个超级框架”，而是：

- 已有框架的边界没收紧
- 基础设施没补齐
- 团队规范还没固化

对这种情况，最划算的路径是增强现有框架，而不是整体替换技术栈。

---

## 13. 最终判断

### 可以继续做

TGReduxKit 可以按照本文档继续改进，而且方向是正确的。

### 但必须有边界

改进方向应该是：

- 收紧
- 补齐
- 轻量增强

而不是：

- 全量框架化
- 全盘 TCA 化
- 引入过度抽象

### 最推荐的三件事

如果只做三件事，优先级如下：

1. 文档与实现统一
2. MainActor Store + 并发模型收敛
3. scoped store + 轻量 cancellation

### 最终结论

对于希望得到一个“比 TCA 轻，但比现在更稳”的框架，TGReduxKit 是可以继续演进的。

正确策略不是替换它，而是把它从“轻量可用”推进到“轻量且可维护”。
