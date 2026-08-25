import Foundation
import TGReduxKit
import TGNavigationStack

// MARK: - Root composition

/// Shopping root reducer. Services are read from `DependencyContext` (see `Dependencies.swift`).
public let shoppingReducer = combineReducers(
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

// MARK: - Feature reducers

private let catalogReducer = Reducer<CatalogState, CatalogAction> { state, action, context in
    switch action {
    case .searchQueryChanged(let query):
        state.searchQuery = query
        state.isSearching = !query.isEmpty
        if query.isEmpty {
            state.isSearching = false
            return .none
        }
        return ShoppingEffects.searchCatalog(
            query: query,
            in: state.allProducts,
            search: context.searchProducts
        )

    case .searchCompleted(let query, let products):
        guard query == state.searchQuery else { return .none }
        state.isSearching = false
        state.visibleProducts = products
        return .none
    }
}

private let cartReducer = Reducer<CartState, CartAction>.sync { state, action in
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

private let featureFlagsReducer = Reducer<FeatureFlagsState, FeatureFlagsAction> { state, action, context in
    switch action {
    case .loadRequested(let source):
        state.isLoading = true
        state.lastSource = source
        return ShoppingEffects.loadFeatureFlags(
            fetch: context.fetchFeatureFlags,
            now: context.date
        )

    case .loaded(let snapshot, let lastUpdated):
        state.snapshot = snapshot
        state.isLoading = false
        state.lastUpdated = lastUpdated
        return .none
    }
}

// MARK: - Cross-cutting (sync + navigation)

private let crossCuttingReducer = Reducer<ShoppingState, ShoppingAction> { state, action, _ in
    switch action {
    case .catalog(.searchCompleted(_, let products)):
        state.catalog.visibleProducts = applyFeatureFlags(
            to: products,
            flags: state.featureFlags.snapshot
        )
        return .none

    case .catalog(.searchQueryChanged(let query)) where query.isEmpty:
        state.catalog.visibleProducts = visibleProducts(
            from: state.catalog.allProducts,
            matching: query,
            flags: state.featureFlags.snapshot
        )
        return .none

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
        return .none

    case .navigation(let navAction):
        navigationReducer(state: &state.navigation, action: navAction)
        return .none

    case .handleDeepLink(let url):
        guard url.scheme == "tgshop",
              url.host == "product",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let idString = queryItems.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idString),
              state.product(for: id) != nil
        else {
            return .none
        }
        navigationReducer(state: &state.navigation, action: .push(.detail(id)))
        return .none

    default:
        return .none
    }
}
