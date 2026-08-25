# 架构分析：DependencyContext 统一注入与 Demo `Shopping` 模块

**范围**：TGReduxKit 5.0 三角架构落地后，业务依赖注入与 Demo 模块边界的选型。  
**相关**：[`ADR_TRIANGULAR_ARCHITECTURE.md`](./ADR_TRIANGULAR_ARCHITECTURE.md)、[`DEFAULT_ACTOR_ISOLATION_AND_REDUX.md`](./DEFAULT_ACTOR_ISOLATION_AND_REDUX.md)、[`EFFECT_GUIDE.md`](./EFFECT_GUIDE.md)。

## 1. 问题回顾

落地 5.0 后，Demo 曾先后出现三类摩擦：

| 阶段 | 做法 | 症状 |
|------|------|------|
| A | Effect / Reducer 写在默认 MainActor 的 App target | `Call to main actor-isolated … in a synchronous nonisolated context` |
| B | 对 Effect 工厂标 `nonisolated` | 警告消失，但把隔离约束推给调用方，不可规模化 |
| C | 拆 `ShoppingDomain` + `ShoppingFeature`，再用 `ShoppingDependencies` 协议袋注入 | 隔离正确，但 **双 target + 双 DI 通道**，对示例过重 |

核心矛盾有两件：

1. **隔离边界**：App 可保留 MainActor 默认；领域 reduce / Effect 必须定义在**无 MainActor 默认**的模块。
2. **注入通道**：框架已有 `DependencyContext`（uuid / date / sleep），再维护 `ShoppingDependencies` 会迫使工厂参数层层穿透。

## 2. 目标形态

```text
App (可默认 MainActor)
  └─ ObservableStore + Views
       │  withDependencies { … }   （可选）
       ▼
actor Store
  └─ DependencyContext ──► Reducer ──► Effect.run(服务闭包)
       ▲
Shopping（Examples 本地 SPM，无 MainActor 默认）
  Models / State / Action
  DependencyKey（函数值）
  shoppingReducer + ShoppingEffects
```

设计原则：

- **一个隔离模块**：Demo 侧只保留产品 `Shopping`。
- **一个 DI 通道**：时钟与业务服务都挂在 `DependencyContext`；通过轻量 `DependencyKey` 扩展。
- **UI 不持服务**：Views 只 `dispatch`；异步 IO 只出现在 `Effect.run`。

## 3. 当前实现要点

### 3.1 Core：`DependencyKey`

[`Sources/TGReduxKitCore/DependencyContext.swift`](../Sources/TGReduxKitCore/DependencyContext.swift)

- `DependencyKey`：`associatedtype Value: Sendable` + `static var liveValue`。
- `DependencyContext` 下标：未写入时回落 `liveValue`；写入后覆盖。
- 既有 `uuid` / `date` / `sleep` 保持一等字段，不强制全部迁到 Key。
- Runtime `Store.withDependencies` / UI `ObservableStore.withDependencies` 使用 `@Sendable` 闭包，避免跨 actor 发送问题。

### 3.2 Demo：单一 `Shopping` 模块

[`Examples/TGReduxKitDemo/Shopping/`](../Examples/TGReduxKitDemo/Shopping/)

- 模型、Reducer、Effect、live 依赖同模块。
- 业务依赖用**函数值**（如 `searchProducts`、`fetchFeatureFlags`），避免 `*Servicing` + `*Dependencies` 袋。
- App 构造：`ObservableStore(initialState:reducer: shoppingReducer)`，不再传 deps 工厂参数。

### 3.3 与三角架构的关系

| 三角层 | 本方案中的角色 |
|--------|----------------|
| Core | 提供可扩展 DI 与 Effect 类型 |
| Runtime | 持有并调度 context；Effect 取消 / latest-wins |
| UI | MainActor 投影；转发 `withDependencies` |
| App 业务模块 | 注册 Key + 写 Reducer；不绑 MainActor |

## 4. 优点

1. **编译期隔离边界**  
   比 `nonisolated` 补丁稳：错误模块放错代码会立刻以隔离诊断暴露，而不是靠约定。

2. **单一 DI 故事**  
   生产路径、测试覆盖、文档示例都指向 `DependencyContext` + `withDependencies`，降低「该用袋还是用 context」的认知税。

3. **Demo 表面积小**  
   一个 SPM 产品即可说明「App 默认 MainActor + 业务非 MainActor」；读者不必理解 Domain/Feature 双库。

4. **可测性够用**  
   测试侧覆盖函数值即可 mock 搜索 / flags，无需协议实现类样板。

5. **与 5.0 Effect 模型对齐**  
   Reducer 同步读 context、返回 Effect；副作用仍在 `run` 内，不把服务塞进 State。

## 5. 缺点与风险

1. **无 TCA 级体验**  
   没有 `@Dependency` 属性包装器、没有测试作用域自动 reset。覆盖依赖要显式 `withDependencies`，大型测试套件需自律。

2. **Key 是样板代码**  
   每个服务要写 `enum …: DependencyKey` + `DependencyContext` extension。体量大时样板会堆积（可用代码生成或共享 helper，当前未做）。

3. **字符串式存储的局限**  
   底层是 `[ObjectIdentifier: any Sendable]`。类型擦除依赖 subscript 强制转换；Key 写错类型会在运行时暴露（设计上由泛型下标约束缓解）。

4. **函数值 vs 协议**  
   Demo 选函数值更短，但多方法服务、有状态 client 用协议作 `Value` 更清晰。文档需说明「Value 可以是协议 existential」，避免读者以为禁止协议。

5. **`withDependencies` 时序**  
   `ObservableStore` 的同步重载会 `Task { await store… }`，与紧随其后的 `dispatch` 之间存在竞态窗口。需要覆盖时优先用 **async** `withDependencies`，或在 init 时传入已配置好的 `DependencyContext`。

6. **历史文档残留**  
   部分 4.x 指南仍写 Middleware + `ShoppingDependencies`；已在 `TESTING_GUIDE` 加 5.0 指针，但未全文改写，新读者可能混淆。

## 6. 与否决方案的对比

| 方案 | 结论 |
|------|------|
| App 内 `nonisolated` Effect | 否决为长期做法；仅应急 |
| Domain + Feature 双 product | 隔离正确但过碎；合并为 `Shopping` |
| 仅工厂闭包捕获、不扩 Core | 可行，但保留双通道；扩展 `DependencyKey` 更统一 |
| 完整 DependencyValues / `@Dependency` | 超出 5.0 首切范围；可作后续增强 |

## 7. 适用建议

**推荐**

- App / Feature 模块：无 MainActor 默认的业务 package（或关闭该 target 的默认隔离）。
- 跨 reducer 共享的服务：`DependencyKey`。
- 一次性接线：工厂捕获仍可接受（见 EFFECT_GUIDE）。

**不推荐**

- 在默认 MainActor 的 App target 写 Reducer / Effect 工厂。
- 再引入第二套 `AppDependencies` 袋与 context 并行作为主路径。
- 把服务实例放进 `State`。

## 8. 后续可选演进

- Init 路径：`ObservableStore(…, dependencies: configured)` 作为覆盖的首选，减少 Task 竞态。
- 测试 helper：`withDependencies` 作用域（进入/退出自动恢复）。
- 若多方法 client 变多：官方示例改用「协议作 `DependencyKey.Value`」的并列样例。

## 9. 结论

当前方案用 **「单一非 MainActor 业务模块 + 可扩展 DependencyContext」** 同时收掉隔离警告与双 DI 噪音，与三角架构一致，代价是 Key 样板与缺少 TCA 级糖。对库的 5.0 首发与 Demo 教学密度是合适折中；更大应用可在同一通道上加厚，而不必回退到协议袋或 MainActor 补丁。
