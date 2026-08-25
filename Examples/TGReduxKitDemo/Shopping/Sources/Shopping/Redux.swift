import Foundation
import TGReduxKit
import TGNavigationStack

// MARK: - Pure reducers (Void)

public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = combineReducers(
    pullback(
        catalogReducer,
        state: \.catalog,
        action: ShoppingAction.catalog,
        extract: { if case .catalog(let a) = $0 { a } else { nil } }
    ),
    pullback(
        cartReducer,
        state: \.cart,
        action: ShoppingAction.cart,
        extract: { if case .cart(let a) = $0 { a } else { nil } }
    ),
    pullback(
        featureFlagsReducer,
        state: \.featureFlags,
        action: ShoppingAction.featureFlags,
        extract: { if case .featureFlags(let a) = $0 { a } else { nil } }
    ),
    crossCuttingReducer
)

private let catalogReducer: Reducer<CatalogState, CatalogAction> = { state, action in
    switch action {
    case .searchQueryChanged(let query):
        state.searchQuery = query
        state.isSearching = !query.isEmpty
        if query.isEmpty {
            state.isSearching = false
        }
    case .searchCompleted(let query, let products):
        guard query == state.searchQuery else { return }
        state.isSearching = false
        state.visibleProducts = products
    }
}

private let cartReducer: Reducer<CartState, CartAction> = { state, action in
    switch action {
    case .add(let product):
        if let index = state.items.firstIndex(where: { $0.product.id == product.id }) {
            state.items[index].quantity += 1
        } else {
            state.items.append(CartItem(product: product))
        }
    case .remove(let offsets):
        for index in offsets.sorted(by: >) {
            state.items.remove(at: index)
        }
    }
}

private let featureFlagsReducer: Reducer<FeatureFlagsState, FeatureFlagsAction> = { state, action in
    switch action {
    case .loadRequested(let source):
        state.isLoading = true
        state.lastSource = source
    case .loaded(let snapshot, let lastUpdated):
        state.snapshot = snapshot
        state.isLoading = false
        state.lastUpdated = lastUpdated
    }
}

private let crossCuttingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .catalog(.searchCompleted(_, let products)):
        state.catalog.visibleProducts = applyFeatureFlags(
            to: products,
            flags: state.featureFlags.snapshot
        )

    case .catalog(.searchQueryChanged(let query)) where query.isEmpty:
        state.catalog.visibleProducts = visibleProducts(
            from: state.catalog.allProducts,
            matching: query,
            flags: state.featureFlags.snapshot
        )

    case .featureFlags(.loaded(let snapshot, _)):
        state.catalog.showsFreeShippingBanner = snapshot.showsFreeShippingBanner
        state.catalog.showsRecommendedBadge = snapshot.showsRecommendedBadge
        state.catalog.isPremiumCatalogOnly = snapshot.hidesBudgetProducts
        state.isExpressCheckoutAvailable = snapshot.isExpressCheckoutEnabled
        state.catalog.visibleProducts = visibleProducts(
            from: state.catalog.allProducts,
            matching: state.catalog.searchQuery,
            flags: snapshot
        )

    case .navigation(let navAction):
        navigationReducer(state: &state.navigation, action: navAction)

    case .handleDeepLink(let url):
        guard url.scheme == "tgshop",
              url.host == "product",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let idString = queryItems.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idString),
              state.product(for: id) != nil
        else {
            return
        }
        navigationReducer(state: &state.navigation, action: .push(.detail(id)))

    default:
        break
    }
}

// MARK: - Middleware (Effects)

public func makeShoppingMiddlewares(
    searchProducts: @escaping @Sendable (String, [Product]) async -> [Product] = ShoppingServices.searchProducts,
    fetchFeatureFlags: @escaping @Sendable () async -> FeatureFlagSnapshot = ShoppingServices.fetchFeatureFlags,
    now: @escaping @Sendable () -> Date = { Date() }
) -> [Middleware<ShoppingState, ShoppingAction>] {
    [
        makeCatalogSearchMiddleware(searchProducts: searchProducts),
        makeFeatureFlagsMiddleware(fetchFeatureFlags: fetchFeatureFlags, now: now)
    ]
}

private func makeCatalogSearchMiddleware(
    searchProducts: @escaping @Sendable (String, [Product]) async -> [Product]
) -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        let base = next(action)
        guard case .catalog(.searchQueryChanged(let query)) = action, !query.isEmpty else {
            return base
        }
        let products = store.state.catalog.allProducts
        return .merge(
            base,
            .debounce(id: ShoppingEffectID.catalogSearch, delay: .milliseconds(300)) {
                let results = await searchProducts(query, products)
                return .catalog(.searchCompleted(query, results))
            }
        )
    }
}

private func makeFeatureFlagsMiddleware(
    fetchFeatureFlags: @escaping @Sendable () async -> FeatureFlagSnapshot,
    now: @escaping @Sendable () -> Date
) -> Middleware<ShoppingState, ShoppingAction> {
    { _, action, next in
        let base = next(action)
        guard case .featureFlags(.loadRequested) = action else {
            return base
        }
        return .merge(
            base,
            .task(id: ShoppingEffectID.featureFlags) {
                let snapshot = await fetchFeatureFlags()
                return .featureFlags(.loaded(snapshot, now()))
            }
        )
    }
}
