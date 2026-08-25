import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

/// Composition Root — assemble dependencies here, never inside Reducer / Store.
public struct ShoppingAppView: View {
    @SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>

    /// Production entry: live services injected into middleware factories.
    public init() {
        self.init(dependencies: .live)
    }

    /// Test / preview entry: swap `ShoppingDependencies` without a DI container.
    public init(dependencies: ShoppingDependencies) {
        let middlewares = makeShoppingMiddlewares(dependencies: dependencies)
        _store = SwiftUI.State(
            initialValue: Store(
                initialState: ShoppingState(),
                reducer: shoppingReducer, // pure — no deps
                middlewares: middlewares  // deps captured inside factories
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
    ShoppingAppView(
        dependencies: ShoppingDependencies(
            featureFlags: PreviewFeatureFlagService()
        )
    )
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
