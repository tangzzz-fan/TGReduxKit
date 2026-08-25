import SwiftUI
import TGReduxKit
import Shopping

/// Shared bootstrap: both manual and Factory Composition Roots end here.
@MainActor
enum ShoppingStoreBootstrap {
    static func makeStore(
        productSearch: any ProductSearching,
        featureFlags: any FeatureFlagFetching,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> Store<ShoppingState, ShoppingAction> {
        Store(
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
