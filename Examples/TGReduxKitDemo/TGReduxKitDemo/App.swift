import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

/// Composition Root — wire each Middleware factory with its deps (5.0; no dependency bag).
public struct ShoppingAppView: View {
    @SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>

    /// Production / preview entry: pass live or mock services directly into factories.
    public init(
        productSearch: any ProductSearching = LiveProductSearchService(),
        featureFlags: any FeatureFlagFetching = LiveFeatureFlagService(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let middlewares: [Middleware<ShoppingState, ShoppingAction>] = [
            makeCatalogSearchMiddleware(productSearch: productSearch),
            makeFeatureFlagsMiddleware(featureFlags: featureFlags, now: now),
            makeAsyncLabMiddleware()
        ]
        _store = SwiftUI.State(
            initialValue: Store(
                initialState: ShoppingState(),
                reducer: shoppingReducer, // pure — no deps
                middlewares: middlewares  // deps already captured in each factory
            )
        )
    }

    public var body: some View {
        TGNavigationStack(
            state: store.state.navigation,
            dispatch: { store.dispatch(.navigation($0)) }
        ) {
            ProductListView()
        } destination: { route in
            switch route {
            case .list:
                ProductListView()
            case .detail(let id):
                ProductDetailView(productID: id)
            case .cart:
                CartView()
            }
        }
        .onOpenURL { url in
            store.dispatch(.handleDeepLink(url))
        }
        .task {
            store.dispatch(.featureFlags(.loadRequested(.launch)))
        }
        .provideStore(store)
    }
}

#Preview("Live") {
    ShoppingAppView()
}

#Preview("Fixed flags") {
    ShoppingAppView(featureFlags: PreviewFeatureFlagService())
}

/// Preview / test double — swap at the Composition Root.
private struct PreviewFeatureFlagService: FeatureFlagFetching {
    func fetchSnapshot() async -> FeatureFlagSnapshot {
        FeatureFlagSnapshot(
            isExpressCheckoutEnabled: true,
            showsFreeShippingBanner: true,
            showsRecommendedBadge: true,
            hidesBudgetProducts: false
        )
    }
}
