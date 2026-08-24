# TGReduxKit 多 Feature 联动实战指南

本文档通过「购物 App」和「车载 App」两个完整场景，展示如何用 TGReduxKit 的 v1.2 ~ v1.4 版本新增能力应对真实业务需求。

---

## 场景一：购物 App（TGReduxKitDemo 启发）

### 业务背景

一个购物 App 包含三个 Feature：

- **Catalog**（商品列表 + 搜索）
- **Cart**（购物车）
- **FeatureFlags**（远端功能开关，控制 Banner、推荐徽标、Express Checkout 的可见性）

三个 Feature 之间有复杂联动：

> 用户在搜索框输入 "Mac" → 防抖 300ms → 远端搜索 → 搜索结果受 Feature Flag 影响（Premium Catalog 开启时隐藏 $500 以下的商品）。用户将商品加入购物车 → 购物车数量更新 → 推荐引擎刷新。

### 1.1 防抖搜索（v1.2 debounce）

用户在搜索框连续输入时，每次按键都会派发 `searchQueryChanged`。如果不加控制，3 个字符 = 3 次网络请求。

**旧写法（手写 sleep + 检查点）：**

```swift
store.runTask(id: "catalog-search") {
    try? await Task.sleep(nanoseconds: 300_000_000)     // ← 容易忘
    guard !Task.isCancelled else { return }              // ← 容易忘
    let results = await searchService.search(query)
    guard !Task.isCancelled else { return }              // ← 容易忘
    await store.dispatch(.catalog(.searchCompleted(query, results)))
}
```

**v1.2 写法（声明式）：**

```swift
store.debounce(id: "catalog-search", milliseconds: 300) {
    let results = await searchService.search(query)
    guard !Task.isCancelled else { return }
    await store.dispatch(.catalog(.searchCompleted(query, results)))
}
```

`debounce` 内部自动处理了「同 ID 取消旧任务 + sleep」，调用者不需要记得 sleep 的正确位置。

### 1.2 搜索接口超时兜底（v1.2 timeout + v1.3 error catching）

搜索接口可能超时。超时后不应让用户看到 3 秒前的旧搜索结果——应该 fallback 到本地过滤。

```swift
store.runTask(
    id: "catalog-search",
    timeoutMs: 5_000,
    fallback: { .catalog(.searchCompleted(query, localFilter(query, in: allProducts))) }
) {
    let results = await searchService.searchProducts(query, in: allProducts)
    guard !Task.isCancelled else { return }
    await store.dispatch(.catalog(.searchCompleted(query, results)))
}
```

链路：
1. 5 秒内远端返回 → `searchCompleted` 带远端结果
2. 5 秒超时 → `fallback` 产生 `searchCompleted` 带本地过滤结果
3. 两种路径最终到达同一个 Action，Reducer 不需要区分来源

> **和上面 debounce 配合**：debounce 保证只有最后一次输入触发搜索，timeout 保证单次搜索不卡死。

### 1.3 推荐服务重试（v1.2 retry）

用户加购后，推荐引擎可能因为网络抖动失败。用指数退避重试 3 次：

```swift
store.runTask(id: "refresh-recs", maxRetries: 3, backoff: .exponential(baseMs: 200)) {
    let recommendations = try await recService.fetch(basedOn: product)
    await store.dispatch(.recommendations(.loaded(recommendations)))
}
```

不用写 `for attempt in 0...3 { try? await ... }` 的样板代码。

### 1.4 Feature Flag 刷新 → 联动 Catalog（v1.3 error catching + v1.4 cross-cutting reducer）

用户点击「Refresh Feature Flags」→ middleware 异步拉取远端配置 → `featureFlagsReducer` 更新 snapshot → **但 CatalogState 的展示字段也需要同步更新**。

> 子 Reducer 的 State 是 `FeatureFlagsState`，它看不到 `CatalogState`。这是 `pullback` 的**设计意图**：强制关注点分离。

**v1.3 错误处理 + v1.4 crossCuttingReducer 的组合用法**：

```swift
// Middleware — 拉取 + 错误回流
func makeFeatureFlagMiddleware(deps: ShoppingDependencies) -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        next(action)

        guard case .featureFlags(.loadRequested) = action else { return }

        store.runTask(id: "feature-flags", catching: { error in
            .featureFlags(.loadFailed(error.localizedDescription))  // ← v1.3 catching
        }) {
            let snapshot = await deps.featureFlagService.fetchSnapshot()
            await store.dispatch(.featureFlags(.loaded(snapshot, Date())))
        }
    }
}

// crossCuttingReducer — 子 Reducer 边界之外的事（v1.4）
let crossCuttingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .featureFlags(.loaded(let snapshot, _)):
        // 子 Reducer（featureFlagsReducer）只更新了 FeatureFlagsState.snapshot。
        // 以下展示字段散布在 CatalogState 和 ShoppingState 顶层——
        // 子 Reducer 看不到这些字段，所以放在父级处理。
        state.catalog.showsFreeShippingBanner = snapshot.showsFreeShippingBanner
        state.catalog.showsRecommendedBadge = snapshot.showsRecommendedBadge
        state.catalog.isPremiumCatalogOnly = snapshot.hidesBudgetProducts
        state.isExpressCheckoutAvailable = snapshot.isExpressCheckoutEnabled
        state.catalog.visibleProducts = visibleProducts(
            from: state.catalog.allProducts,
            matching: state.catalog.searchQuery,
            flags: snapshot
        )

    case .featureFlags(.loadFailed(let message)):
        // 错误回流到 state，UI 层可以展示 toast/banner
        state.errorMessage = message
    }
}

// 组装（v1.4 combineReducers + pullback）
let shoppingReducer = combineReducers(
    pullback(catalogReducer,      state: \.catalog,      extract: { if case .catalog(let a) = $0      { a } else { nil } }),
    pullback(cartReducer,         state: \.cart,         extract: { if case .cart(let a) = $0         { a } else { nil } }),
    pullback(featureFlagsReducer, state: \.featureFlags, extract: { if case .featureFlags(let a) = $0 { a } else { nil } }),
    crossCuttingReducer  // ← 处理子 Reducer 做不到的事
)
```

**全局错误上报（v1.3）：**

```swift
let store = Store(
    initialState: ShoppingState(),
    reducer: shoppingReducer,
    middlewares: [
        makeFeatureFlagMiddleware(deps: deps),
        errorReportingMiddleware(
            extract: { action in
                if case .featureFlags(.loadFailed(let msg)) = action {
                    return (NSError(domain: "App", code: 0, userInfo: [NSLocalizedDescriptionKey: msg]), "featureFlags")
                }
                return nil
            },
            reporter: { error, source in
                CrashReporter.record(error, source: source)
            }
        ),
    ]
)
```

### 1.5 跨 Feature 通信（v1.3 CrossFeature 文档）

购物车加购 → 触发推荐刷新。Feature A（Cart）不知道 Feature B（Recommendations）的存在——由父级 middleware 协调：

```swift
let crossFeatureMiddleware: Middleware<ShoppingState, ShoppingAction> = { store, action, next in
    next(action)

    guard case .cart(.add(let product)) = action else { return }

    store.runTask(id: "refresh-recs", maxRetries: 3, backoff: .exponential(baseMs: 200)) {
        let recs = try await recService.fetch(basedOn: product)
        await store.dispatch(.recommendations(.loaded(recs)))
    }
}
```

### 1.6 用 TestStore 覆盖完整购物流程（v1.2 TestStore）

不启动 App，不同步等待异步操作：

```swift
@Test func fullShoppingFlow() {
    let store = TestStore(initialState: ShoppingState(), reducer: shoppingReducer)

    // 搜索
    store.send(.catalog(.searchQueryChanged("iPhone")))
    #expect(store.state.catalog.isSearching == true)

    // 搜索结果返回（模拟 middleware 回流）
    store.send(.catalog(.searchCompleted("iPhone", [iPhoneProduct])))
    #expect(store.state.catalog.isSearching == false)
    #expect(store.state.catalog.visibleProducts.count == 1)

    // 加购
    store.send(.cart(.add(iPhoneProduct)))
    #expect(store.state.cart.totalQuantity == 1)

    // 查看完整状态历史
    let history = store.replayHistory()
    #expect(history.count == 4)  // initial → search → completed → add
}
```

---

## 场景二：车载 App

### 业务背景

一个车载 App 包含四个 Feature：

- **Climate**（空调控制：温度、风速、模式）
- **Navigation**（导航：目的地、路线、ETA）
- **Media**（媒体播放：曲目、音量、播放状态）
- **DriveMode**（驾驶模式：Eco / Normal / Sport，影响空调和媒体的行为）

联动需求：

> 用户切换到 Sport 模式 → 空调自动增大风速（降温优先）→ 媒体音量自动降低（驾驶专注）。导航开始逐向导航 → 媒体音量降低至 30%。导航结束 → 音量恢复。

### 2.1 throttle：方向盘滚轮调节音量

方向盘上的滚轮每转动 1 格就产生一个事件。如果在 200ms 内连续滚动了 10 格，不应该发 10 次 `volumeChanged` Action——只需要最后一次的值：

```swift
store.throttle(id: "volume-wheel", milliseconds: 200) {
    await store.dispatch(.media(.setVolume(targetVolume)))
}
```

和 debounce 的区别：throttle 立即执行第一次，然后在「窗口结束且本次操作完成」之前忽略同 ID 后续调用。用户转动滚轮时，第一格立刻生效，不会在慢操作未完成时叠加工。

### 2.2 retry + timeout：导航路线请求

车载网络不稳定（隧道、地库）。路线请求需要重试 + 超时兜底：

```swift
store.runTask(
    id: "calc-route",
    timeoutMs: 8_000,
    fallback: { .navigation(.routeFailed(.timeout)) },
    maxRetries: 2,
    backoff: .exponential(baseMs: 500)
) {
    let route = try await navigationService.calculateRoute(from: origin, to: destination)
    await store.dispatch(.navigation(.routeReady(route)))
}
```

链路：
1. 正常 → `routeReady`
2. 网络抖动 → 指数退避重试（500ms → 1s）
3. 2 次重试仍失败 + 8 秒超时 → `routeFailed(.timeout)` fallback
4. `catching` 未使用——`fallback` 已经覆盖了超时路径

### 2.3 驾驶模式联动三个 Feature（v1.4 cross-cutting reducer）

这是整个车载 App 中跨 Feature 最密集的场景。DriveMode 的一个 Action 会同时改变 Climate、Media、Navigation 三个子状态。

```swift
// 子 Reducer——各自独立
let climateReducer: Reducer<ClimateState, ClimateAction> = { state, action in
    switch action {
    case .setTemperature(let temp): state.targetTemp = temp
    case .setFanSpeed(let speed):   state.fanSpeed = speed
    default: break
    }
}

let mediaReducer: Reducer<MediaState, MediaAction> = { state, action in
    switch action {
    case .setVolume(let vol):   state.volume = vol
    case .play, .pause, .next, .previous: ...
    default: break
    }
}

let navigationReducer: Reducer<NavState, NavAction> = { state, action in
    switch action {
    case .routeReady(let route): state.currentRoute = route; state.isNavigating = true
    case .navigationEnded:       state.currentRoute = nil;  state.isNavigating = false
    default: break
    }
}

let driveModeReducer: Reducer<DriveModeState, DriveModeAction> = { state, action in
    switch action {
    case .setMode(let mode): state.mode = mode
    }
}
```

**跨 Feature 联动都在父级 crossCuttingReducer：**

```swift
let driveModeCrossCutting: Reducer<CarState, CarAction> = { state, action in
    switch action {
    // ──── DriveMode 联动 ────
    case .driveMode(.setMode(let mode)):
        state.driveMode.mode = mode  // ← pullback 的 driveModeReducer 已完成自己的状态更新
        switch mode {
        case .sport:
            state.climate.fanSpeed = 5          // 空调最大风（降温优先）
            state.climate.targetTemp = 20       // 目标低温
            state.media.volume = max(3, state.media.volume - 5)  // 降低音量
        case .eco:
            state.climate.fanSpeed = 2          // 节能风速
            state.media.volume = min(15, state.media.volume + 3)  // 恢复音量
        case .normal:
            break  // 不干预
        }

    // ──── 导航联动 ────
    case .navigation(.routeReady):
        state.navigation.isNavigating = true
        state.media.navVolumeOverride = Int(Double(state.media.volume) * 0.3)  // 降至 30%

    case .navigation(.navigationEnded):
        state.navigation.isNavigating = false
        state.media.navVolumeOverride = nil  // 解除音量限制

    default: break
    }
}

let carReducer = combineReducers(
    pullback(climateReducer,     state: \.climate,     extract: { if case .climate(let a) = $0     { a } else { nil } }),
    pullback(mediaReducer,       state: \.media,       extract: { if case .media(let a) = $0       { a } else { nil } }),
    pullback(navigationReducer,  state: \.navigation,  extract: { if case .navigation(let a) = $0  { a } else { nil } }),
    pullback(driveModeReducer,   state: \.driveMode,   extract: { if case .driveMode(let a) = $0   { a } else { nil } }),
    driveModeCrossCutting
)
```

**为什么子 Reducer 不做这件事？**

`climateReducer` 的 State 类型是 `ClimateState`，它看不到 `DriveModeState.mode`。即便我们把 `CarState` 整个传进去，子 Reducer 也不知道其他 Feature 的字段含义——它只应该关心空调温度。

**`crossCuttingReducer` 是唯一能看到完整 State 树的地方**，这就是 pullback 要强制边界的原因。

### 2.4 用 TestStore 验证驾驶模式联动

```swift
@Test func sportModeFansUpAndVolumeDown() {
    let initialState = CarState(
        climate: ClimateState(fanSpeed: 2, targetTemp: 24),
        media: MediaState(volume: 10),
        driveMode: DriveModeState(mode: .normal)
    )

    let store = TestStore(initialState: initialState, reducer: carReducer)

    store.send(.driveMode(.setMode(.sport)))

    // 空调自动调节
    #expect(store.state.climate.fanSpeed == 5)
    #expect(store.state.climate.targetTemp == 20)

    // 驾驶模式已切换
    #expect(store.state.driveMode.mode == .sport)

    // 媒体音量降低（驾驶专注）
    #expect(store.state.media.volume == 5)  // 10 - 5 = 5
}

@Test func navigationReducesVolumeAndRestores() {
    let store = TestStore(initialState: CarState(
        media: MediaState(volume: 12),
        navigation: NavState(isNavigating: false)
    ), reducer: carReducer)

    // 开始导航
    store.send(.navigation(.routeReady(Route(eta: 300))))
    #expect(store.state.navigation.isNavigating == true)
    #expect(store.state.media.navVolumeOverride == 3)  // 30% of 12 ≈ 3

    // 导航结束
    store.send(.navigation(.navigationEnded))
    #expect(store.state.navigation.isNavigating == false)
    #expect(store.state.media.navVolumeOverride == nil)  // 解除覆盖
}
```

### 2.5 全局错误上报：车载诊断

车载 App 通常有诊断上报系统。所有 Feature 的错误可以统一收集：

```swift
let diagnosticsMiddleware = errorReportingMiddleware(
    extract: { action in
        switch action {
        case .navigation(.routeFailed(let reason)):
            return (NSError(domain: "Car.Navigation", code: 0,
                            userInfo: [NSLocalizedDescriptionKey: reason]), "navigation")
        case .media(.playbackFailed(let error)):
            return (error, "media")
        case .climate(.sensorError(let code)):
            return (NSError(domain: "Car.Climate", code: code,
                            userInfo: [NSLocalizedDescriptionKey: "Sensor failure"]), "climate")
        default:
            return nil
        }
    },
    reporter: { error, source in
        DiagnosticsService.log(error, source: source, timestamp: Date())
    }
)
```

---

## 版本能力映射

| 能力 | 版本 | 购物 App 场景 | 车载 App 场景 |
|------|------|-------------|-------------|
| `TestStore` | v1.2 | §1.6 购物流程测试 | §2.4 驾驶模式联动测试 |
| `debounce` | v1.2 | §1.1 搜索防抖 | — |
| `throttle` | v1.2 | — | §2.1 方向盘滚轮音量 |
| `retry` | v1.2 | §1.3 推荐服务重试 | §2.2 路线请求重试 |
| `timeout` | v1.2 | §1.2 搜索超时 fallback | §2.2 路线超时 fallback |
| `ErrorAction` / `catching` | v1.3 | §1.4 Flag 拉取错误回流 | — |
| `errorReportingMiddleware` | v1.3 | §1.4 全局错误上报 | §2.5 车载诊断上报 |
| 跨 Feature 通信 | v1.3 | §1.5 Cart → Recommendations | §2.3 DriveMode → Climate+Media |
| `combineReducers` + `pullback` | v1.4 | §1.4 组装子 Reducer | §2.3 组装四个 Feature |
| `crossCuttingReducer` | v1.4 | §1.4 Flag→Catalog 映射 | §2.3 DriveMode 联动三 Feature |

---

## 小结

TGReduxKit v1.2 ~ v1.4 的新增能力围绕一个核心思路：

> **让常见模式从「手写样板代码」变成「声明式调用」，同时不引入新的概念负担。**

两个场景的完整代码可以在以下位置找到：

- 购物 App：`../Examples/TGReduxKitDemo/TGReduxKitDemo/Redux.swift`
- 测试覆盖：`../Tests/TGReduxKitTests/`（`TestStoreTests`、`AsyncPrimitivesTests`、`ErrorHandlingTests`、`CrossFeatureTests`、`ReducerCompositionTests`）
