# 跨 Feature 通信

Feature A 的变化要触发 Feature B 的副作用时，用根级协调 Middleware（返回 `Effect`），不要让 Feature 互相持有引用。

## 推荐：父级 Middleware 转发

```swift
func makeCrossFeatureMiddleware(
    recommendations: RecommendationService
) -> Middleware<ShoppingState, ShoppingAction> {
    { _, action, next in
        let base = next(action)
        guard case .cart(.add(let product)) = action else { return base }
        return .merge(
            base,
            .task(id: "refresh-recommendations") {
                .recommendations(.updated(
                    await recommendations.basedOn(product)
                ))
            }
        )
    }
}
```

把 feature-specific middleware 与 coordinating middleware 一起在 Composition Root 组装。

## 备选：跨切 Reducer

若只需同步改多个子树（无 IO），用根级 `crossCuttingReducer` 监听已嵌入的 Action（Demo `Shopping` 中 Flag 加载后刷新 catalog 可见列表即此模式）。

副作用仍走 Middleware；跨切 Reducer 只做纯状态派生。
