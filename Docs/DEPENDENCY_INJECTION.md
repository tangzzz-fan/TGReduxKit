# 依赖注入（无框架必选；可选对接 Factory）

> **5.0 现行**：每个 Middleware **工厂函数**在构造时接收自己的依赖；Composition Root 组装。
> TGReduxKit **不内置** DI 容器，**领域层不感知** DI 框架。可用纯参数接线，
> 也可用 [Factory](https://github.com/hmlongco/Factory) 等框架**只在门口解析**。

## 分层规则

| 层级 | 依赖 | 方式 |
|------|------|------|
| **Reducer** | 不允许 | 纯 `(inout State, Action) -> Void` |
| **Middleware** | 允许且必须 | `makeFooMiddleware(api:)` 参数注入，闭包捕获 |
| **Effect 闭包** | 允许 | 捕获 `Sendable` 依赖 |
| **Store** | 无业务依赖 | 只持有 state / reducer / middlewares |
| **DI 框架** | 仅 Composition Root | 解析服务 → 传入 Middleware 工厂；**不要** `@Injected` 进 Reducer |

| 做法 | OK? |
|------|-----|
| Root 里 `container.api()` 再 `makeAPIMiddleware(api:)` | ✅ |
| Middleware 工厂参数捕获服务 | ✅ |
| `@Injected` / `Container` 写进 Reducer | ❌ |
| `Store` 持有 `Container` | ❌ |
| `*Dependencies` 袋二次分发 | ❌ |

> **不要用 `*Dependencies` 袋。** 依赖必须逐个具名传参 —— `makeStore` 的签名本身就是编译期契约，
> 袋子会把这个契约重新藏起来。5.0.1 已移除 Demo 里的 `ShoppingDependencies` 袋。

## Composition Root 的位置

Demo 里**只有一个** App 视图，它只接受**已组装好的服务**，对 DI 框架零感知：

```swift
ShoppingAppView(
    productSearch: any ProductSearching,
    featureFlags: any FeatureFlagFetching,
    now: @escaping @Sendable () -> Date
)
```

「服务从哪来」由 `DemoRootView` 决定 —— **全工程唯一接触 DI 容器的地方**：

```text
DemoRootView（唯一 Composition Root）
   ├─ 显式实参 ────────────────────► LiveProductSearchService()
   │                                  LiveFeatureFlagService()
   │                                  { Date() }
   │
   └─ 容器解析 ─ Container.shared ─► productSearch / featureFlags / now
                        │
                        ▼  两条路都进同一个
        ShoppingStoreBootstrap.makeStore(productSearch:featureFlags:now:)
                        ├─ makeCatalogSearchMiddleware(productSearch:)
                        ├─ makeFeatureFlagsMiddleware(featureFlags:now:)
                        └─ makeAsyncLabMiddleware()
                        │
                        ▼
                     Store
```

两条路的差异**只在「服务从哪来」**，不在架构。`makeStore` 的签名始终是唯一的编译期依赖契约，
容器解析不会渗透到 View / Store / Middleware。

## Store 的构建时机：不要在 `init` 里 `State(initialValue:)`

Composition Root 是 SwiftUI `View`，而 `View` 是**值类型** —— 父视图每次重新求值都会重新调用
它的 `init`。因此这样写是错的：

```swift
// ❌ 每次父视图重绘都白构建一个 Store，然后被丢弃
public init(productSearch:featureFlags:now:) {
    _store = SwiftUI.State(
        initialValue: ShoppingStoreBootstrap.makeStore(...)
    )
}
```

`State` 只保留**第一次**写入的值，后续写入全部丢弃。于是 `makeStore` 会随父视图重绘次数线性执行，
产出的 `Store` 被静默扔掉。

实测（真实 SwiftUI 层级 + `NSWindow`，触发 5 次父视图重绘）：

| 写法 | `init` 调用 | **昂贵构建**执行 |
|------|------------|-----------------|
| 在 `init` 里 `State(initialValue:)` | 6 | **6**（5 次被丢弃） |
| `@State` 持有 optional + `.onAppear` 守卫 | 6 | **1** |

正确写法 —— 把「持有」移出「描述」阶段：

```swift
public struct ShoppingAppView: View {
    private let productSearch: any ProductSearching
    private let featureFlags: any FeatureFlagFetching
    private let now: @Sendable () -> Date

    @SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>?

    public var body: some View {
        ZStack {
            if let store { ShoppingRootHost(store: store) }
        }
        .onAppear {
            guard store == nil else { return }   // onAppear 可能重复触发
            store = ShoppingStoreBootstrap.makeStore(
                productSearch: productSearch, featureFlags: featureFlags, now: now
            )
        }
    }
}
```

三个要点：

1. **`init` 是描述阶段**（廉价、高频），**构建对象图是持有阶段**（昂贵、一次）。
   把持有操作写进描述阶段是范畴错误 —— 这才是根因，不是"性能小问题"。
2. **用 `ZStack` 而非 `Group`**：容器身份稳定，`.onAppear` 不会随内容切换而重挂。
   `ZStack` 在首帧内容为空时 `.onAppear` **仍会触发**（已实测）。
3. **`guard store == nil`** 不可省：`onAppear` 会因导航进出重复触发，Store 只应构建一次。

> 本 Demo 里 `Store.init` 无副作用，所以旧写法的代价只是白分配几个对象。
> 但只要有一个 middleware 工厂带副作用（注册通知观察者、起定时器、开文件句柄），
> **每一帧就会泄漏一份**。作为参考实现，这个模式必须是对的。

这条约束**编译期表达不了、运行期也没有副作用可观测**，所以它由测试钉住：
`TGReduxKitDemoTests/StoreConstructionTimingTests.swift`（3 个用例）。

| 用例 | 断言 |
|------|------|
| `constructingViewDoesNotBuildStore` | `init` 不得构建 Store —— **这条抓「改回 `init` 里构建」的回归** |
| `evaluatingBodyDoesNotBuildStore` | `body` 不得构建 Store —— 抓「把 `makeStore` 直接写进 `body`」 |
| `makeStoreAdvancesCounter` | 对照组：探针本身有效，否则前两条会变成假阳性 |

为支持断言，`ShoppingStoreBootstrap` 里有一个 `#if DEBUG` 探针 `makeStoreCallCount`。

> **为什么不测「托管后恰好构建一次」？** 那条路径的失败（删掉 `.onAppear`）会导致 Store 永不构建、
> 界面永久空白 —— 是**响亮**的失败，跑一次 Demo 就能看到。只有**静默**的失败才值得写测试。

## `now` / `uuid` 为什么没有默认值

`makeFeatureFlagsMiddleware(featureFlags:now:)` 与 `makeStore(..., now:)` 都**要求显式传入** `now`。

默认参数（`now: … = { Date() }`）是一种**隐式依赖**：省略它仍能编译、仍能运行，
`Date()` 会悄悄进入业务路径 —— 这正是本架构要消灭的东西。要求显式传，成本为零。

## 对接 Factory / FactoryKit

在 **App 层**注册（`DI/Container+Shopping.swift`），`Shopping` 模块仍不依赖 Factory：

```swift
import FactoryKit
import Shopping

extension Container {
    var productSearch: Factory<any ProductSearching> {
        self { LiveProductSearchService() }
    }
    var featureFlags: Factory<any FeatureFlagFetching> {
        self { LiveFeatureFlagService() }
    }
    var now: Factory<@Sendable () -> Date> {
        self { { Date() } }
    }
}
```

### ⚠️ 可注册域 ⊆ `Sendable`

Factory 的注册闭包类型是 `@Sendable @isolated(any) () -> T`，其隔离**从闭包所在上下文推断**。
`Container` 是非隔离类型，所以扩展属性里的裸闭包是**非隔离**的 —— 注册一个 `@MainActor` 隔离的类型会**直接编译失败**。

实测（Swift 6.4 / Xcode 27 / Factory 2.5.3）：

| 场景 | 结果 |
|------|------|
| `@MainActor` 服务 · 无注解 · Swift 6 | ❌ `ActorIsolatedCall` |
| `@MainActor` 服务 · 无注解 · Swift 5 mode | ❌ 同样是 error，不是 warning |
| `@MainActor` 服务 · 无注解 · `defaultIsolation(MainActor)` | ❌ |
| `@MainActor` 服务 · **仅属性**注解 `@MainActor` | ❌ |
| `@MainActor` 服务 · **仅闭包**注解 `@MainActor in` | ✅ |
| `Sendable` 服务 · 无注解 | ✅ |
| 闭包注解后 · 从 nonisolated 上下文解析 | ✅ |

三条结论：

1. **唯一有效的修法是注解闭包**：`self { @MainActor in SomeMainActorService() }`。
   属性上的 `@MainActor` 既不必要也不充分。
2. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 救不了它**（见下节）。
3. 失败发生在**注册点**，不在解析点 —— 从 nonisolated 上下文解析是允许的。

实践上：**把要注册的服务写成 `Sendable`（`struct` / `actor` / `@Sendable` 闭包）**，
Demo 的 `ProductSearching` / `FeatureFlagFetching` 都是 `Sendable` 协议，`now` 是 `@Sendable () -> Date`。

### 与默认 MainActor 的联动（重要）

App target 默认 MainActor 时，**在该 target 内定义的服务类型会隐式 `@MainActor`**，
从而无法直接注册进 Factory。Demo 的 Factory 示例之所以能编译，是因为它的服务住在
`Shopping` 这个**刻意没有 MainActor 默认**的 SPM target 里。

> 把 `LiveProductSearchService` 移进 app target → Factory 注册立刻编译失败。

详见 [DEFAULT_ACTOR_ISOLATION_AND_REDUX.md](./DEFAULT_ACTOR_ISOLATION_AND_REDUX.md)。

### ⚠️ Factory 2.5.3 自身在 Swift 6 下的告警

用 `swift build`（Swift 6 语言模式）编译 Factory 2.5.3 源码时，**Factory 自己的源码**会产出 9 条：

```text
Factory.swift:146:31: warning: converting @isolated(any) function of type
  '@isolated(any) @Sendable () -> T' to synchronous function type '@Sendable (Void) -> T'
  is not allowed; this will be an error in a future Swift language mode
  [#ConversionFromIsolatedAnyToSynchronous]
```

这不是本库或 Demo 的代码问题（Demo 与 TGReduxKit 零 error / 零 warning），
而是依赖自身的前向兼容债务：**未来某个 Swift 语言模式会把它变成硬错误**。
选择 Factory 时应把它计入长期维护成本。

### Preview / Test 覆盖

**推荐：换实参，不要改全局容器。**

```swift
#Preview("Factory 接线 / 预览覆盖") {
    ShoppingAppView(
        productSearch: Container.shared.productSearch(),
        featureFlags: PreviewFeatureFlagService(),   // ← 只换这一个
        now: Container.shared.now()
    )
}
```

因为容器解析只发生在 Composition Root，View 的实参就是覆盖点 —— 不需要动容器。

若确实需要改容器（通常只在测试里），用 Factory 的 `@TaskLocal` 隔离
（`Container.shared` 本身就是 `@TaskLocal`）：

```swift
Container.$shared.withValue(Container()) {
    Container.shared.featureFlags.register { MockFeatureFlagService() }
    // 断言都在这个作用域内
}
```

- `Container.shared.featureFlags.register { … }` 是**永久替换**，会污染同进程内的其它 Preview / 测试。
- `Container.shared.preview { }` **不做隔离**（源码里就是 `transform(self)`），别拿它当隔离手段。
- `Scope.singleton` 同样是 `@TaskLocal`，单例缓存也需要一起隔离。

## 结论：要不要和 Factory 组合使用

### 地基：容器能替掉什么，不能替掉什么

`Middleware` 的类型里**没有容器参数**：

```swift
public typealias Middleware<State, Action> = @MainActor (
    any StoreType<State, Action>,
    Action,
    @escaping @MainActor (Action) -> Effect<Action>
) -> Effect<Action>
```

所以容器**永远无法**回答「middleware 怎么拿到依赖」—— 依赖只能被工厂闭包捕获。
容器唯一能回答的是「**Composition Root 从哪里拿到工厂的实参**」。

> **Factory 替换的是接线的取数方式，不是接线本身。** 这是下面所有结论的地基。

### 先纠正一个流行的误诊

常见说法是「Factory 的全局容器与 `@MainActor @Observable` Store 的生命周期管理容易打架」。
**这条不成立。** Store 的生命周期由 SwiftUI 的 `@State` 持有，Factory 从不接触 Store，
也不应该把 Store 注册进容器。二者没有生命周期交集。

真实摩擦在**别处**，共两条：

1. **可注册域 ⊆ `Sendable`** —— 注册 `@MainActor` 服务直接编译失败（见上文实测矩阵）。
   这是**服务**的约束，不是 Store 生命周期的约束。
2. **依赖关系从编译期可见退化为运行期可查** —— 这条是真的，且是引入容器的主要代价。

### 容器解决的问题，本架构已经解决过了

DI 容器的价值随三件事增长：**图深度**、**每服务的消费者数量**、**运行时可替换性**。
而工厂闭包 DI 已经把这三件事在 middleware 层消掉了：

| 容器通常提供的 | 工厂闭包 DI 的等价物 | 谁更好 |
|---|---|---|
| 运行时解析（缺失 → 崩溃） | `makeStore` 签名（缺失 → **编译失败**） | 闭包 DI |
| `register` 换实现（全局、永久） | 换实参（局部、无副作用） | 闭包 DI |
| `@TaskLocal` 隔离容器 | 每个测试自己 new 一个 | 闭包 DI（零仪式） |
| 单例作用域 | Root 里 `let api = …` 传给两处 | 打平 |

所以在 **Redux 边界以内**，容器是净负担。

### 容器仍然值钱的地方：服务层自己的深图

`LiveAPI` → `HTTPClient` → `URLSession` → `Logger` → `Config`，手工穿构造器很痛。
这是 Factory 的**真实**价值 —— 但注意：**这是服务层的问题，不是 Redux 的问题**，
它发生在 Composition Root 的**下游**。用 Factory 解决它、用普通构造器解决它、
或用一个 `LiveServices` 工厂函数解决它，**都不改变 middleware 的依赖契约**。

### 决策规则

**用 Factory，当且仅当满足以下任一条：**

- 服务层图深到手工穿构造器已经真的痛（经验值：≥3 层，或同一服务在多处被构造）
- 某个资源需要**单例生命周期**，且构造昂贵、消费者众多
- 已有 Factory 代码库，**一致性**收益大于下述成本

**不要用 Factory，如果：**

- Composition Root 一屏写得完（像本 Demo）
- App target 默认 MainActor 隔离 —— 该 target 内所有类型隐式 `@MainActor`，全部不可注册，
  你会一直在跟注册约束搏斗
- 你希望测试隔离零仪式、依赖关系编译期可见

**引进 Factory 时必须一并接受的两条债：**

1. 服务必须写成 `Sendable`，且往往要挪进一个**无 MainActor 默认**的 SPM target（见上文）。
2. Factory 2.5.3 自身在 Swift 6 下产出 9 条前向兼容告警，未来语言模式会变成硬错误（见上文）。

### 无论选哪个，铁律不变

**Factory 不得跨过 Redux 边界。**

- 不进 `Reducer`
- 不进 `Middleware` 工厂签名
- 不进 `Store`

它只能出现在 Composition Root，且只回答「实参从哪来」。
`DemoRootView` 就是这个铁律的物理形态 —— 全工程唯一接触 `Container.shared` 的地方。

### 一句话

> **默认不要。** 工厂闭包 DI 与 DI 容器是**替代关系**，不是互补关系 ——
> 本架构已经消掉了容器要解决的问题。只有当你**服务层自己的图**深到手工接线成为负担时，
> 才把 Factory 引到 Composition Root，并且永远只让它停在那里。

## Reducer 需要时间 / UUID

由 Middleware 工厂参数注入的 `now` / `uuid` 写入 Action，不要在 Reducer 里直接 `Date()`。

## 相对 TCA `@Dependency`

| | 本方案 | TCA Dependency |
|--|--------|----------------|
| 解析时机 | 工厂参数（+ 可选 Factory 在 Root） | 运行时键查找 |
| 全局状态 | 可选，且仅限 Composition Root | `DependencyValues` |
| 测试 | 换工厂实参；或 `withValue` 隔离容器 | 改全局注册表 |

**原则**：无论有没有 Factory，依赖都停在架构门口；Reducer / Store 保持干净。
