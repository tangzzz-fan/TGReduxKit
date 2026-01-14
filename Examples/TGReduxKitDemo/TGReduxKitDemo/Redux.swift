import Foundation
import TGReduxKit
import SwiftUI

// MARK: - State

public struct ShoppingState: Equatable {
    public var products: [Product] = []
    public var cartItems: [CartItem] = []
    public var navigation: NavigationState<ShoppingRoute> = .init(path: [])
    
    // Helper to find product by ID (useful for detail view)
    public func product(for id: UUID) -> Product? {
        products.first { $0.id == id }
    }
    
    public init() {
        // Mock Data
        self.products = [
            Product(name: "iPhone 15", price: 999, description: "Latest Apple Phone", imageName: "iphone"),
            Product(name: "MacBook Pro", price: 1999, description: "Powerful Laptop", imageName: "laptopcomputer"),
            Product(name: "AirPods Pro", price: 249, description: "Noise Cancelling", imageName: "airpods"),
            Product(name: "Apple Watch", price: 399, description: "Smart Watch", imageName: "applewatch")
        ]
    }
}

// MARK: - Action

public enum ShoppingAction: Equatable {
    case addToCart(Product)
    case removeFromCart(IndexSet)
    case navigation(NavigationAction<ShoppingRoute>)
    case handleDeepLink(URL)
}

// MARK: - Reducer

public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .addToCart(let product):
        if let index = state.cartItems.firstIndex(where: { $0.product.id == product.id }) {
            state.cartItems[index].quantity += 1
        } else {
            state.cartItems.append(CartItem(product: product))
        }
        
    case .removeFromCart(let offsets):
        state.cartItems.remove(atOffsets: offsets)
        
    case .navigation(let navAction):
        navigationReducer(state: &state.navigation, action: navAction)
        
    case .handleDeepLink(let url):
        // Scheme: tgshop://product?id={uuid}
        guard url.scheme == "tgshop",
              url.host == "product",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let idString = queryItems.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idString) else {
            return
        }
        
        // Strategy: Reset to root then push detail
        // Or if we want to keep history: just push
        // Here we choose to push directly.
        // Check if product exists
        if state.product(for: id) != nil {
            navigationReducer(state: &state.navigation, action: .push(.detail(id)))
        }
    }
}
