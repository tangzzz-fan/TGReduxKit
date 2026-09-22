# TGReduxKitDemo

> **TGReduxKit 5.0**：纯 Reducer + Middleware→Effect。DI 演示**两种接线方式，同一个 App 视图**。

## Composition Root（启动后可选）

**全工程唯一接触 DI 容器的地方是 `DemoRootView`。** 两种接线产出同一个 `ShoppingAppView`：

| 接线方式 | 说明 |
|---------|------|
| **显式实参** | 直接构造服务传进去：`LiveProductSearchService()` / `LiveFeatureFlagService()` / `{ Date() }` |
| **Factory 容器解析** | `Container.shared.productSearch()` 等解析后再传入**同一组参数** |

```swift
// DemoRootView —— 差异只在这几行
ShoppingAppView(                                          // 显式实参
    productSearch: LiveProductSearchService(),
    featureFlags: LiveFeatureFlagService(),
    now: { Date() }
)

ShoppingAppView(                                          // Factory 容器解析
    productSearch: Container.shared.productSearch(),
    featureFlags: Container.shared.featureFlags(),
    now: Container.shared.now()
)
```

两条路都进 `ShoppingStoreBootstrap.makeStore(productSearch:featureFlags:now:)` ——
**`makeStore` 的签名始终是唯一的编译期依赖契约**，容器解析不会渗透到 View / Store / Middleware。
`Shopping` SPM **不依赖** Factory，注册只写在 App 层的 `DI/Container+Shopping.swift`。

### 预览覆盖 = 换实参

```swift
#Preview("Factory 接线 / 预览覆盖") {
    ShoppingAppView(
        productSearch: Container.shared.productSearch(),
        featureFlags: PreviewFeatureFlagService(),   // ← 只换这一个
        now: Container.shared.now()
    )
}
```

不要用 `Container.shared.featureFlags.register { … }` —— 那是**永久替换**，会污染同进程的其它 Preview / 测试。

### ⚠️ Factory 的可注册域 ⊆ `Sendable`

Factory 的注册闭包是 `@Sendable` 且隔离从闭包上下文推断，**注册 `@MainActor` 隔离的类型会编译失败**。
本 Demo 能编译，是因为服务住在 `Shopping` 这个**没有 MainActor 默认**的 SPM target 里 ——
把它们移进默认 MainActor 的 app target 就会立刻报错。

实测矩阵与修法见仓库 `Docs/DEPENDENCY_INJECTION.md`。

### `now` 没有默认值

`makeStore(..., now:)` 与 `makeFeatureFlagsMiddleware(featureFlags:now:)` 都要求显式传入。
默认参数是隐式依赖 —— 省略它仍能编译，`Date()` 会悄悄进入业务路径。

### Store 只在「首次出现」时构建

`ShoppingAppView` **不在 `init` 里**调用 `makeStore`：

```swift
@SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>?

var body: some View {
    ZStack { if let store { ShoppingRootHost(store: store) } }
        .onAppear {
            guard store == nil else { return }        // onAppear 可能重复触发
            store = ShoppingStoreBootstrap.makeStore(...)
        }
}
```

原因：`View` 是值类型，父视图每次重绘都会重跑 `init`，而 `State` 只保留**第一次**写入 ——
旧写法会随重绘次数线性地白构建 `Store` 并静默丢弃。实测（真实 SwiftUI 层级，5 次重绘）：

| 写法 | 昂贵构建次数 |
|------|-------------|
| `init` 里 `State(initialValue:)` | **6** |
| `@State` optional + `.onAppear` 守卫 | **1** |

这条约束编译期表达不了、运行期也没有副作用可观测，因此由
`TGReduxKitDemoTests/StoreConstructionTimingTests.swift` 钉住
（靠 `ShoppingStoreBootstrap` 里的 `#if DEBUG` 探针 `makeStoreCallCount`）。

## 异步流

| Demo | 机制 |
|------|------|
| 搜索 | `debounce` + 清空 `.cancel` + `isCancelled` + query guard |
| Feature Flags | `task`；可模拟失败 |
| Async Lab | 长任务 Cancel；Respect `Task.isCancelled` 对比泄漏 |

## Run

打开 `TGReduxKitDemo.xcodeproj`（已加 SPM：`Factory` → product **FactoryKit**）。

- App target 与两个测试 target：`SWIFT_VERSION = 6.0`；App `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `Shopping` 领域包：Swift 6，**无** MainActor 默认（见 `Docs/DEFAULT_ACTOR_ISOLATION_AND_REDUX.md`）

> 注意：`Shopping` 依赖本地路径 `../../../../TGNavigationStack`。该仓库不在本机时，Demo 无法构建。

详见仓库 `Docs/DEPENDENCY_INJECTION.md`。

## 工程文件生成（XcodeGen）

`project.yml` 是工程的**唯一声明源**；`.xcodeproj` 是它的产物。

```bash
cd Examples/TGReduxKitDemo
./regenerate.sh          # 等价于 USER=$(id -un) xcodegen generate，但补了两个坑
```

`regenerate.sh` 不是多余的包装，它处理两件事：

1. **`USER` 必须显式设置。** 本机 shell 环境里 `USER` 为空（`whoami` 正常但变量不存在），
   XcodeGen 取不到就打印 `Couldn't find current username` 并 **exit 2，什么都不生成** ——
   看起来像权限问题，其实不是。
2. **`Package.resolved` 不在 XcodeGen 的产出里。** 它钉住 Factory 的解析版本（当前 2.5.3），
   直接生成会丢掉它、导致 Xcode 重新解析。脚本先备份、生成后还原。

**前提**：`../../../TGNavigationStack` 必须存在 —— XcodeGen 会校验本地包路径，
缺失时报 `Spec validation error: Invalid local package "TGNavigationStack"`。

`project.yml` 里值得注意的三点：

| 声明 | 为什么 |
|------|--------|
| `projectFormat: xcode16_0` | 产出 `objectVersion 77`，是 `PBXFileSystemSynchronizedRootGroup` 的前提 |
| `type: syncedFolder` | 保留 Xcode 16 的**目录同步**语义：新增 `.swift` 不需要重新生成工程 |
| 项目级 `SWIFT_VERSION: "6.0"` | 一处声明、三个 target 继承（原先要在 pbxproj 里改 6 处） |

> 首次迁移时已逐项比对过生成结果与手写 pbxproj 的**有效构建设置**：
> 三个 target × Debug/Release **零丢失、零改值**。差异只有两类：
> 去掉了一处冗余的重复 `TGReduxKit` 链接，以及补上若干等于 Xcode 默认值的设置。
