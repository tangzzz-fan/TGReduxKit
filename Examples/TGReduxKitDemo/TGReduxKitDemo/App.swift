import SwiftUI
import TGReduxKit

// MARK: - Shopping App Entry

/// The entry point for the Shopping Example App.
/// Note: Since this is inside a package, you would typically wrap this in a struct that conforms to `App`
/// or use it as a root view in your application.
public struct ShoppingAppView: View {
    @State private var store = Store(
        initialState: ShoppingState(),
        reducer: shoppingReducer,
        middlewares: [loggingMiddleware, analyticsMiddleware]
    )
    
    public init() {}
    
    public var body: some View {
        TGNavigationStack(
            state: Binding(
                get: { store.state.navigation },
                set: { _ in } // Navigation is one-way driven by state in this example, but binding allows two-way sync if needed
            )
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
        .provideStore(store)
    }
}

// MARK: - Preview

#Preview {
    ShoppingAppView()
}
