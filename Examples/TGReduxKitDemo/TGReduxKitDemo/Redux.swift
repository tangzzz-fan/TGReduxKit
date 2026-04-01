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

// MARK: - Reducer

public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .catalog(let catalogAction):
        switch catalogAction {
        case .searchQueryChanged(let query):
            state.catalog.searchQuery = query
            state.catalog.isSearching = !query.isEmpty

            if query.isEmpty {
                state.catalog.visibleProducts = visibleProducts(
                    from: state.catalog.allProducts,
                    matching: query,
                    flags: state.featureFlags.snapshot
                )
                state.catalog.isSearching = false
            }

        case .searchCompleted(let query, let products):
            guard query == state.catalog.searchQuery else { return }
            state.catalog.visibleProducts = applyFeatureFlags(
                to: products,
                flags: state.featureFlags.snapshot
            )
            state.catalog.isSearching = false
        }

    case .cart(let cartAction):
        switch cartAction {
        case .add(let product):
            if let index = state.cart.items.firstIndex(where: { $0.product.id == product.id }) {
                state.cart.items[index].quantity += 1
            } else {
                state.cart.items.append(CartItem(product: product))
            }

        case .remove(let offsets):
            state.cart.items.remove(atOffsets: offsets)
        }

    case .featureFlags(let featureFlagsAction):
        switch featureFlagsAction {
        case .loadRequested(let source):
            state.featureFlags.isLoading = true
            state.featureFlags.lastSource = source

        case .loaded(let snapshot, let lastUpdated):
            state.featureFlags.snapshot = snapshot
            state.featureFlags.isLoading = false
            state.featureFlags.lastUpdated = lastUpdated
            state.catalog.showsFreeShippingBanner = snapshot.showsFreeShippingBanner
            state.catalog.showsRecommendedBadge = snapshot.showsRecommendedBadge
            state.catalog.isPremiumCatalogOnly = snapshot.hidesBudgetProducts
            state.isExpressCheckoutAvailable = snapshot.isExpressCheckoutEnabled
            state.catalog.visibleProducts = visibleProducts(
                from: state.catalog.allProducts,
                matching: state.catalog.searchQuery,
                flags: snapshot
            )
        }

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
