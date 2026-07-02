import Foundation
import TGReduxKit
import SwiftUI

// MARK: - State

public struct ShoppingState: Equatable {
    public var catalog: CatalogState
    public var cart: CartState = .init()
    public var featureFlags: FeatureFlagsState = .init()
    public var isExpressCheckoutAvailable = false
    public var navigation: NavigationState<ShoppingRoute> = .init(path: [])

    public func product(for id: UUID) -> Product? {
        catalog.allProducts.first { $0.id == id }
    }

    public init() {
        let products = [
            Product(name: "iPhone 15", price: 999, description: "Latest Apple Phone", imageName: "iphone"),
            Product(name: "MacBook Pro", price: 1999, description: "Powerful Laptop", imageName: "laptopcomputer"),
            Product(name: "AirPods Pro", price: 249, description: "Noise Cancelling", imageName: "airpods"),
            Product(name: "Apple Watch", price: 399, description: "Smart Watch", imageName: "applewatch")
        ]
        let snapshot = FeatureFlagSnapshot.default
        self.featureFlags = FeatureFlagsState(snapshot: snapshot)
        self.catalog = CatalogState(
            allProducts: products,
            visibleProducts: visibleProducts(from: products, matching: "", flags: snapshot),
            showsFreeShippingBanner: snapshot.showsFreeShippingBanner,
            showsRecommendedBadge: snapshot.showsRecommendedBadge,
            isPremiumCatalogOnly: snapshot.hidesBudgetProducts
        )
        self.isExpressCheckoutAvailable = snapshot.isExpressCheckoutEnabled
    }
}

public struct CatalogState: Equatable {
    public var allProducts: [Product]
    public var visibleProducts: [Product]
    public var searchQuery: String = ""
    public var isSearching: Bool = false
    public var showsFreeShippingBanner: Bool = false
    public var showsRecommendedBadge: Bool = false
    public var isPremiumCatalogOnly: Bool = false

    public init(
        allProducts: [Product] = [],
        visibleProducts: [Product] = [],
        searchQuery: String = "",
        isSearching: Bool = false,
        showsFreeShippingBanner: Bool = false,
        showsRecommendedBadge: Bool = false,
        isPremiumCatalogOnly: Bool = false
    ) {
        self.allProducts = allProducts
        self.visibleProducts = visibleProducts
        self.searchQuery = searchQuery
        self.isSearching = isSearching
        self.showsFreeShippingBanner = showsFreeShippingBanner
        self.showsRecommendedBadge = showsRecommendedBadge
        self.isPremiumCatalogOnly = isPremiumCatalogOnly
    }
}

public struct CartState: Equatable {
    public var items: [CartItem] = []

    public init(items: [CartItem] = []) {
        self.items = items
    }

    public var totalQuantity: Int {
        items.reduce(0) { $0 + $1.quantity }
    }

    public var totalPrice: Decimal {
        items.reduce(0) { $0 + $1.product.price * Decimal($1.quantity) }
    }
}

public struct FeatureFlagsState: Equatable {
    public var snapshot: FeatureFlagSnapshot
    public var isLoading: Bool
    public var lastUpdated: Date?
    public var lastSource: FeatureFlagLoadSource?

    public init(
        snapshot: FeatureFlagSnapshot = .default,
        isLoading: Bool = false,
        lastUpdated: Date? = nil,
        lastSource: FeatureFlagLoadSource? = nil
    ) {
        self.snapshot = snapshot
        self.isLoading = isLoading
        self.lastUpdated = lastUpdated
        self.lastSource = lastSource
    }
}

public struct FeatureFlagSnapshot: Equatable, Sendable {
    public var isExpressCheckoutEnabled: Bool
    public var showsFreeShippingBanner: Bool
    public var showsRecommendedBadge: Bool
    public var hidesBudgetProducts: Bool

    public init(
        isExpressCheckoutEnabled: Bool,
        showsFreeShippingBanner: Bool,
        showsRecommendedBadge: Bool,
        hidesBudgetProducts: Bool
    ) {
        self.isExpressCheckoutEnabled = isExpressCheckoutEnabled
        self.showsFreeShippingBanner = showsFreeShippingBanner
        self.showsRecommendedBadge = showsRecommendedBadge
        self.hidesBudgetProducts = hidesBudgetProducts
    }

    public static let `default` = FeatureFlagSnapshot(
        isExpressCheckoutEnabled: false,
        showsFreeShippingBanner: true,
        showsRecommendedBadge: true,
        hidesBudgetProducts: false
    )
}

public enum FeatureFlagLoadSource: String, Equatable, Sendable {
    case launch = "Launch"
    case manualRefresh = "Manual Refresh"
}

// MARK: - Action

public enum ShoppingAction: Equatable {
    case catalog(CatalogAction)
    case cart(CartAction)
    case featureFlags(FeatureFlagsAction)
    case navigation(NavigationAction<ShoppingRoute>)
    case handleDeepLink(URL)
}

public enum CatalogAction: Equatable {
    case searchQueryChanged(String)
    case searchCompleted(String, [Product])
}

public enum CartAction: Equatable {
    case add(Product)
    case remove(IndexSet)
}

public enum FeatureFlagsAction: Equatable {
    case loadRequested(FeatureFlagLoadSource)
    case loaded(FeatureFlagSnapshot, Date)
}

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
        // visible products are reassembled by the parent reducer (pullback
        // preserves the rest of parent state, so feature flags are readable).
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
        state.items.remove(atOffsets: offsets)
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

/// A reducer that handles cross-cutting actions, ties feature flags into catalog
/// presentation fields, and falls back to `navigationReducer` for routing.
///
/// # pullback 的使用场景
///
/// `catalogReducer`、`cartReducer`、`featureFlagsReducer` 三个 Feature
/// 各自只操作自己的子 State (`CatalogState` / `CartState` / `FeatureFlagsState`)。
/// 它们**无法直接访问父级 State 中的其他字段**。
///
/// 当一个 Feature 的 Action 需要联动其他 Feature 的状态时（如 Feature Flag
/// 刷新后需要更新 `CatalogState` 的展示控制字段），这个联动逻辑应该放在
/// **父级 Reducer** 中处理——即这里的 `crossCuttingReducer`。
///
/// `pullback` 通过 `extract` 闭包充当"路由表"：只有匹配到的子 Action 才会被
/// 转发到对应的子 Reducer。未匹配的 Action（如 `handleDeepLink`）由根 Reducer
/// 直接处理。
public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = combineReducers(
    // Feature-level reducers — each only sees its own state slice
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

    // Cross-cutting: 子 Reducer 无法覆盖的逻辑
    crossCuttingReducer
)

/// Cross-cutting work that belongs at the root level.
///
/// 这里处理三类父级 Reducer 特有的职责：
///
/// 1. **Feature Flag → 派生展示状态映射**：`CatalogState` 的 Banner/徽标/
///    过滤字段来源于 `FeatureFlagSnapshot`，子 Reducer 不持有 flag 快照引用，
///    所以在父级统一映射。
///
/// 2. **Action → 多子 State 联动**：Feature Flag 刷新后同时更新 CatalogState
///    的展示字段 *和* `isExpressCheckoutAvailable`（属于 ShoppingState 顶层）。
///    这是子 Reducer 做不到的——它们只看到自己的 state slice。
///
/// 3. **路由 / Deep Link**：`navigationReducer` 和 `handleDeepLink` 直接操作
///    根 State 的导航字段。
private let crossCuttingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .catalog(let catalogAction):
        // Post-process catalog search results with current feature flags
        if case .searchCompleted(let query, let products) = catalogAction {
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
        // Map remote flags → presentation fields spread across CatalogState
        // and top-level ShoppingState — something only the root can do.
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

func visibleProducts(
    from products: [Product],
    matching query: String,
    flags: FeatureFlagSnapshot
) -> [Product] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

    let searchResults: [Product]
    if normalizedQuery.isEmpty {
        searchResults = products
    } else {
        searchResults = products.filter { product in
            product.name.localizedCaseInsensitiveContains(normalizedQuery)
            || product.description.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    return applyFeatureFlags(to: searchResults, flags: flags)
}

func applyFeatureFlags(
    to products: [Product],
    flags: FeatureFlagSnapshot
) -> [Product] {
    guard flags.hidesBudgetProducts else {
        return products
    }

    return products.filter { $0.price >= 500 }
}
