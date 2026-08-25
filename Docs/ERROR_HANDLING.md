# 错误处理指南

异步失败在 Middleware / Effect 闭包里 catch，转成显式 Action；Reducer 只写状态。

## 模式一：Effect 内 catch → 失败 Action

```swift
func makeUserMiddleware(repo: UserRepository) -> Middleware<AppState, AppAction> {
    { _, action, next in
        let base = next(action)
        guard case .loadUser = action else { return base }
        return .merge(
            base,
            .task(id: "load-user") {
                do { return .userLoaded(try await repo.fetchUser()) }
                catch { return .userLoadFailed(error.localizedDescription) }
            }
        )
    }
}
```

## 模式二：全局上报

挂载 `errorReportingMiddleware`，从 Action 抽出错误信息上报（不 catch 异步 throws）：

```swift
errorReportingMiddleware(
    extract: { action in
        if case .userLoadFailed(let message) = action {
            return (SimpleError(message), "user")
        }
        return nil
    },
    reporter: { error, source in analytics.report(error, source: source) }
)
```

Demo / Debug product：`TGReduxKitDebug`。
