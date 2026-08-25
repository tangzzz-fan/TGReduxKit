import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

// MARK: - A) Manual Composition Root (no DI framework)

/// Pass services as arguments — TGReduxKit 5.0 default teaching path.
public struct ManualDIShoppingAppView: View {
    @SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>

    public init(
        productSearch: any ProductSearching = LiveProductSearchService(),
        featureFlags: any FeatureFlagFetching = LiveFeatureFlagService(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        _store = SwiftUI.State(
            initialValue: ShoppingStoreBootstrap.makeStore(
                productSearch: productSearch,
                featureFlags: featureFlags,
                now: now
            )
        )
    }

    public var body: some View {
        ShoppingRootHost(store: store)
    }
}

// MARK: - Shared shell (UI only)

struct ShoppingRootHost: View {
    @Bindable var store: Store<ShoppingState, ShoppingAction>

    var body: some View {
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

#Preview("Manual / Live") {
    ManualDIShoppingAppView()
}

#Preview("Manual / Fixed flags") {
    ManualDIShoppingAppView(featureFlags: PreviewFeatureFlagService())
}

struct PreviewFeatureFlagService: FeatureFlagFetching {
    func fetchSnapshot() async -> FeatureFlagSnapshot {
        FeatureFlagSnapshot(
            isExpressCheckoutEnabled: true,
            showsFreeShippingBanner: true,
            showsRecommendedBadge: true,
            hidesBudgetProducts: false
        )
    }
}
