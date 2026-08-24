import SwiftUI
import TGReduxKit
import TGReduxKitNavigation

// MARK: - Shopping App Entry

/// The entry point for the Shopping Example App.
/// Note: Since this is inside a package, you would typically wrap this in a struct that conforms to `App`
/// or use it as a root view in your application.
public struct ShoppingAppView: View {
    @State private var store: Store<ShoppingState, ShoppingAction>
    @State private var catalogStore: ScopedStore<CatalogState, CatalogAction>
    @State private var cartStore: ScopedStore<CartState, CartAction>
    @State private var featureFlagStore: ScopedStore<FeatureFlagsState, FeatureFlagsAction>

    public init(dependencies: ShoppingDependencies = .init()) {
        let store = Store(
            initialState: ShoppingState(),
            reducer: shoppingReducer,
            middlewares: [
                loggingMiddleware,
                analyticsMiddleware,
                makeProductSearchMiddleware(dependencies: dependencies),
                makeFeatureFlagMiddleware(dependencies: dependencies)
            ]
        )

        _store = State(initialValue: store)
        _catalogStore = State(initialValue: store.scope(state: \.catalog, action: ShoppingAction.catalog))
        _cartStore = State(initialValue: store.scope(state: \.cart, action: ShoppingAction.cart))
        _featureFlagStore = State(
            initialValue: store.scope(state: \.featureFlags, action: ShoppingAction.featureFlags)
        )
    }

    public var body: some View {
        TGNavigationStack(
            state: store.state.navigation,
            dispatch: { store.dispatch(.navigation($0)) }
        ) {
            ProductListView()
                .provideStore(catalogStore)
        } destination: { route in
            switch route {
            case .list:
                ProductListView()
                    .provideStore(catalogStore)
            case .detail(let id):
                ProductDetailView(productID: id)
            case .cart:
                CartView()
                    .provideStore(cartStore)
            }
        }
        .onOpenURL { url in
            store.dispatch(.handleDeepLink(url))
        }
        .task {
            store.dispatch(.featureFlags(.loadRequested(.launch)))
        }
        .provideStore(featureFlagStore)
        .provideStore(store)
    }
}

// MARK: - Preview

#Preview {
    ShoppingAppView()
}
