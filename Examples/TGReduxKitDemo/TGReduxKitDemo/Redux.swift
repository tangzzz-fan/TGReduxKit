import Foundation
import TGReduxKit
import TGNavigationStack
import ShoppingDomain

// MARK: - Feature Reducers

/// Catalog state — self-contained.  Does not know about Cart or FeatureFlags.
let catalogReducer: Reducer<CatalogState, CatalogAction> = { state, action in
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
    }
}

/// Cart state — pure, self-contained.  Does not know about Catalog or FeatureFlags.
let cartReducer: Reducer<CartState, CartAction> = { state, action in
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

/// Feature-flags state — loading / snapshot management only.
let featureFlagsReducer: Reducer<FeatureFlagsState, FeatureFlagsAction> = { state, action in
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

// MARK: - Root Reducer (composite)

/// Ties feature reducers together, maps flags into catalog presentation fields,
/// and delegates routing to `navigationReducer`.
///
/// # pullback 的使用场景
///
/// `catalogReducer`、`cartReducer`、`featureFlagsReducer` 三个 Feature
/// 各自只操作自己的子 State。跨 Feature 联动放在父级 `crossCuttingReducer`。
public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = combineReducers(
    pullback(catalogReducer,
        state: \.catalog,
        extract: { if case .catalog(let a) = $0 { a } else { nil } }
    ),
    pullback(cartReducer,
        state: \.cart,
        extract: { if case .cart(let a) = $0 { a } else { nil } }
    ),
    pullback(featureFlagsReducer,
        state: \.featureFlags,
        extract: { if case .featureFlags(let a) = $0 { a } else { nil } }
    ),
    crossCuttingReducer
)

/// Cross-cutting work that belongs at the root level.
private let crossCuttingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .catalog(let catalogAction):
        if case .searchCompleted(_, let products) = catalogAction {
            state.catalog.visibleProducts = applyFeatureFlags(
                to: products,
                flags: state.featureFlags.snapshot
            )
        }
        if case .searchQueryChanged(let query) = catalogAction, query.isEmpty {
            state.catalog.visibleProducts = visibleProducts(
                from: state.catalog.allProducts,
                matching: query,
                flags: state.featureFlags.snapshot
            )
        }

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
              let id = UUID(uuidString: idString) else {
            return
        }
        if state.product(for: id) != nil {
            navigationReducer(state: &state.navigation, action: .push(.detail(id)))
        }

    default:
        break
    }
}
