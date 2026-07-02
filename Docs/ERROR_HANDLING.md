# 错误处理指南

## 模式一：Middleware 内 catch → dispatch 错误 Action

直接在 middleware 的 `runTask(catching:)` 中将错误转为 action：

```swift
let userMiddleware: Middleware<AppState, AppAction> = { store, action, next in
    next(action)

    guard case .loadUser = action else { return }

    store.runTask(id: "load-user", catching: { error in
        .user(.loadFailed(error.localizedDescription))
    }) {
        let user = try await userRepository.fetchUser()
        await store.dispatch(.user(.loaded(user)))
    }
}
```

## 模式二：全局错误上报

使用 `errorReportingMiddleware` 将所有匹配的错误 action 上报到日志/分析服务：

```swift
let store = Store(
    initialState: AppState(),
    reducer: appReducer,
    middlewares: [
        // Feature middleware...
        errorReportingMiddleware(
            extract: { action in
                if case .user(.loadFailed(let msg)) = action {
                    return (NSError(domain: "App", code: 0, userInfo: [NSLocalizedDescriptionKey: msg]), "user")
                }
                if case .catalog(.searchFailed(let msg)) = action {
                    return (NSError(domain: "App", code: 0, userInfo: [NSLocalizedDescriptionKey: msg]), "catalog")
                }
                return nil
            },
            reporter: { error, source in
                CrashReporter.log(error, source: source)
            }
        ),
    ]
)
```

## 推荐组合

| 场景 | 推荐 |
|------|------|
| 业务错误恢复 | 模式一（`runTask(catching:)` — 错误回流为 action） |
| 全局日志/监控 | 模式二（`errorReportingMiddleware` — 拦截上报） |
| 两者都需要 | 叠加使用：先 catching 回流，再 middleware 上报 |
