import SwiftUI
import TGReduxKit
import Shopping

/// Shared bootstrap: both wiring styles end here.
///
/// 这是两条 Composition Root 的**唯一汇合点** —— 签名本身就是依赖契约。
/// `now` 无默认值：默认参数是隐式依赖，会绕过"门口显式组装"的约束。
@MainActor
enum ShoppingStoreBootstrap {
    #if DEBUG
    /// 测试探针：`makeStore` 的调用次数。
    ///
    /// 存在的理由：「Store 只在视图**首次出现**时构建一次」这条约束，
    /// 编译期表达不了，运行期也没有副作用可观测 —— 没有计数器，
    /// 有人把 `ShoppingAppView` 改回「在 `init` 里构建」时不会有任何东西报警
    /// （后果是静默的：每次父视图重绘白造一个 Store 再丢弃）。
    ///
    /// 见 `TGReduxKitDemoTests/StoreConstructionTimingTests.swift`。
    static var makeStoreCallCount = 0
    #endif

    static func makeStore(
        productSearch: any ProductSearching,
        featureFlags: any FeatureFlagFetching,
        now: @escaping @Sendable () -> Date
    ) -> Store<ShoppingState, ShoppingAction> {
        #if DEBUG
        makeStoreCallCount += 1
        #endif

        return Store(
            initialState: ShoppingState(),
            reducer: shoppingReducer,
            middlewares: [
                makeCatalogSearchMiddleware(productSearch: productSearch),
                makeFeatureFlagsMiddleware(featureFlags: featureFlags, now: now),
                makeAsyncLabMiddleware()
            ]
        )
    }
}
