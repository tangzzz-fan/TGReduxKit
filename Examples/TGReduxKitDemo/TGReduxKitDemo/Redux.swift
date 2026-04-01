import Foundation
import TGReduxKit
import SwiftUI

// MARK: - State

public struct ShoppingState: Equatable {
    public var catalog: CatalogState
    public var cart: CartState = .init()
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
        self.catalog = CatalogState(allProducts: products, visibleProducts: products)
    }
}

public struct CatalogState: Equatable {
    public var allProducts: [Product]
    public var visibleProducts: [Product]
    public var searchQuery: String = ""
    public var isSearching: Bool = false

    public init(
        allProducts: [Product] = [],
        visibleProducts: [Product] = [],
        searchQuery: String = "",
        isSearching: Bool = false
    ) {
        self.allProducts = allProducts
        self.visibleProducts = visibleProducts
        self.searchQuery = searchQuery
        self.isSearching = isSearching
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

// MARK: - Action

public enum ShoppingAction: Equatable {
    case catalog(CatalogAction)
    case cart(CartAction)
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

// MARK: - Reducer

public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .catalog(let catalogAction):
        switch catalogAction {
        case .searchQueryChanged(let query):
            state.catalog.searchQuery = query
            state.catalog.isSearching = !query.isEmpty

            if query.isEmpty {
                state.catalog.visibleProducts = state.catalog.allProducts
                state.catalog.isSearching = false
            }

        case .searchCompleted(let query, let products):
            guard query == state.catalog.searchQuery else { return }
            state.catalog.visibleProducts = products
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
