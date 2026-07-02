# 时间旅行调试指南

TGReduxKit v2.0 引入 `TimeTravelRecorder` — 以 **middleware 形式** 录制每个 Action 派发前后的 State 快照。不侵入现有架构，生产环境不挂载 zero-cost。

---

## 场景一：购物 App — 追踪总价计算 Bug

### 问题

QA 报告：加购 `Widget($10)` → 加购 `Gadget($20)` → 移除 `Widget` 后，购物车总价显示 `$20` 而非期望的 `$20`（实际上是 **总价追踪逻辑正确**，但 QA 想要验证中间态）。

### 用法：录制完整购物流程

```swift
let recorder = TimeTravelRecorder<ShoppingState, ShoppingAction>()
let store = Store(
    initialState: ShoppingState(),
    reducer: shoppingReducer,
    middlewares: [timeTravelMiddleware(recorder: recorder)]
)

// 正常操作
store.dispatch(.cart(.add(Product(name: "Widget", price: 10))))
store.dispatch(.cart(.add(Product(name: "Gadget", price: 20))))
store.dispatch(.cart(.remove(offsets: IndexSet(integer: 0))))

// 查看时间线
for entry in recorder.entries {
    print("#\(entry.index): \(entry.action) → total = \(entry.stateAfter.cart.totalPrice)")
}
// 输出:
// #0: add(Widget)  → total = 10
// #1: add(Gadget)  → total = 30
// #2: remove(Widget) → total = 20
```

### 用法：跳转到出错前的状态

```swift
// 怀疑是 remove 操作有问题？回到 remove 之前
if let stateBeforeRemove = recorder.snapshot(at: 1) {
    // stateBeforeRemove.cart.totalPrice == 30
    // 手动重放 remove 逻辑验证...
}

// 或者回到最初状态
if let initialState = recorder.initialState {
    // 重新开始调试
}
```

### 用法：筛选特定 Action

```swift
// 只看购物车相关的 Action
let cartActions = recorder.filter { action in
    if case .cart = action { return true }
    return false
}
print("购物车操作共 \(cartActions.count) 次")

// 带 Flag 联动的时间线 —— 找出 Flag 刷新发生时 Catalog 的变化
let flagEntries = recorder.filter { action in
    if case .featureFlags(.loaded) = action { return true }
    return false
}
for entry in flagEntries {
    print("Flag loaded → freeShipping: \(entry.stateAfter.catalog.showsFreeShippingBanner)")
}
```

### 集成：Debug 菜单中嵌入 TimelineInspector

```swift
// 在 App 入口挂载
@main
struct ShoppingApp: App {
    let recorder = TimeTravelRecorder<ShoppingState, ShoppingAction>()
    let store: Store<ShoppingState, ShoppingAction>

    init() {
        store = Store(
            initialState: ShoppingState(),
            reducer: shoppingReducer,
            middlewares: [
                timeTravelMiddleware(recorder: recorder),  // ← 挂载录制器
                // ... 其他 middleware
            ]
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .provideStore(store)
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        NavigationLink("⏱ Timeline") {
                            TimelineInspector(
                                recorder: recorder,
                                actionLabel: { action in
                                    switch action {
                                    case .cart(.add(let p)):   return "🛒 加购 \(p.name)"
                                    case .cart(.remove):        return "🗑 移除商品"
                                    case .catalog(.searchQueryChanged(let q)): return "🔍 搜索: \(q)"
                                    case .featureFlags(.loaded): return "🚩 Flag 刷新"
                                    default: return "\(action)"
                                    }
                                },
                                stateSummary: { state in
                                    "Catalog: \(state.catalog.visibleProducts.count) 件, Cart: \(state.cart.totalQuantity) 件 ($\(state.cart.totalPrice))"
                                }
                            )
                        }
                    }
                }
                #endif
        }
    }
}
```

### 调试真实 Bug 的工作流

```
1. 用户报告 "加购后总价不对"
2. 打开 TimelineInspector，搜索 add/remove 操作
3. 找到异常的 Action，点击查看 before/after State
4. 用 recorder.snapshot(at:) 跳回出问题之前的状态
5. 手动重放逻辑，定位根因
6. 用 TestStore 写回归测试
```

---

## 场景二：车载 App — 验证 DriveMode 联动

### 问题

Sport 模式下空调风速应该自动升到 5，媒体音量降低 5。但测试中有时看到风速为 4——可能某个 Action 覆盖了联动设置。

### 用法：录制模式切换全过程

```swift
let recorder = TimeTravelRecorder<CarState, CarAction>()
let store = Store(
    initialState: CarState(
        climate: ClimateState(fanSpeed: 2, targetTemp: 24),
        media: MediaState(volume: 10),
        driveMode: DriveModeState(mode: .normal)
    ),
    reducer: carReducer,
    middlewares: [timeTravelMiddleware(recorder: recorder)]
)

// 切换 Sport → 空调/媒体联动
store.dispatch(.driveMode(.setMode(.sport)))

// 用户手动调低风速（覆盖了联动值）
store.dispatch(.climate(.setFanSpeed(3)))

// 导航开始 → 媒体降音
store.dispatch(.navigation(.routeReady(Route(eta: 600))))

// ──── 查看完整时间线 ────
for entry in recorder.entries {
    let mode = entry.stateAfter.driveMode.mode
    let fan = entry.stateAfter.climate.fanSpeed
    let vol = entry.stateAfter.media.volume
    let navVol = entry.stateAfter.media.navVolumeOverride

    print("#\(entry.index): fan=\(fan) vol=\(vol) navVol=\(navVol ?? -1) mode=\(mode)")
}
// 输出:
// #0: fan=5 vol=5 navVol=-1 mode=sport        ← 联动正确：Sport → fan↑, vol↓
// #1: fan=3 vol=5 navVol=-1 mode=sport        ← 用户手动覆盖风速
// #2: fan=3 vol=5 navVol=1 mode=sport         ← 导航降音：30% × 5 = 1（media.volume 已经是 5）
```

### 用法：导出 JSON 做离线分析

```swift
// CarState 和 CarAction 遵循 Codable 时可以直接导出
let jsonData = try recorder.exportJSON()
// 写入文件供离线分析或发给团队
try jsonData.write(to: URL(filePath: "/tmp/timeline.json"))

// JSON 结构:
// [
//   {
//     "index": 0,
//     "timestamp": "2026-07-03T01:30:00Z",
//     "action": "{\"driveMode\":{\"setMode\":{\"sport\":{}}}}",
//     "stateBefore": { "climate": {"fanSpeed": 2, ...}, ... },
//     "stateAfter":  { "climate": {"fanSpeed": 5, ...}, ... }
//   },
//   ...
// ]
```

### 用法：maxEntries 防止内存溢出

车载 App 长时间运行（数小时），录制无上限会累积大量快照：

```swift
recorder.maxEntries = 500  // 只保留最近 500 条
```

超出后自动丢弃最旧的条目。

---

## 生产环境建议

| 环境 | 配置 |
|------|------|
| Debug 开发 | `TimeTravelRecorder` 常驻, `TimelineInspector` 嵌入 debug 菜单 |
| TestFlight | `isRecording = false` 默认关闭，通过隐藏手势切换 |
| App Store | **不挂载 `timeTravelMiddleware`** — 零开销 |

推荐使用 `#if DEBUG` 编译标志控制 middleware 是否挂载：

```swift
var middlewares: [Middleware<AppState, AppAction>] = [
    // 生产 middleware...
]

#if DEBUG
let debugRecorder = TimeTravelRecorder<AppState, AppAction>()
middlewares.append(timeTravelMiddleware(recorder: debugRecorder))
#endif
```

---

## 与 TestStore 的配合

| | TestStore | TimeTravelRecorder |
|---|---|---|
| 用途 | 单元测试 — 给定 Input 断言 Output | 调试 — 录制真实 App 运行时的 Action 序列 |
| 环境 | 测试代码 | App 运行时 |
| 产出 | 测试通过/失败 | 时间线 + State 快照 |
| 最佳实践 | CI 中运行 | Debug 构建中嵌入 |

两者互补：TimeTravel 帮忙**发现**线上/调试中的问题，TestStore **锁定**回归。

---

## 小结

`TimeTravelRecorder` 聚焦一个简单问题：

> "App 现在出了问题，但我不知道是哪个 Action 导致的。"

通过录制每个 Action 的前后 State 快照，你可以在不动用断点的情况下快速回溯状态变更链路——**有方向地排查，而不是逐帧猜测**。
