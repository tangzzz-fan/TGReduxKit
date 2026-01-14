import Foundation
import TGReduxKit

// MARK: - Logging Middleware

/// A simple middleware that logs every action and the resulting state.
public let loggingMiddleware: Middleware<ShoppingState, ShoppingAction> = { store, action, next in
    print("➡️ [Action]: \(action)")
    
    // Pass the action to the next middleware or reducer
    next(action)
    
    print("✅ [State Updated]: \(store.state)")
}

// MARK: - Analytics Middleware (Mock)

/// A middleware that simulates tracking specific actions to an analytics service.
public let analyticsMiddleware: Middleware<ShoppingState, ShoppingAction> = { store, action, next in
    next(action)
    
    switch action {
    case .addToCart(let product):
        print("📊 [Analytics] User added \(product.name) to cart.")
        
    case .navigation(let navAction):
        if case .push(let route) = navAction {
            print("📊 [Analytics] User navigated to \(route).")
        }
        
    default:
        break
    }
}
