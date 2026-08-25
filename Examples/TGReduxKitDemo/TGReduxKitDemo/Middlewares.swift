import Foundation
import TGReduxKit
import TGNavigationStack
import ShoppingDomain

// MARK: - Logging Middleware

public let loggingMiddleware: Middleware<ShoppingState, ShoppingAction> = actionLoggingMiddleware()

// MARK: - Search Middleware

public func makeProductSearchMiddleware(
    dependencies: ShoppingDependencies
) -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        next(action)

        guard case .catalog(.searchQueryChanged(let query)) = action else { return }
        guard !query.isEmpty else { return }

        let allProducts = store.state.catalog.allProducts

        store.runTask(id: "catalog-search") {
            try? await Task.sleep(nanoseconds: 300_000_000)

            guard !Task.isCancelled else { return }

            let results = await dependencies.productSearchService.searchProducts(
                query: query,
                in: allProducts
            )

            guard !Task.isCancelled else { return }
            await store.dispatch(.catalog(.searchCompleted(query, results)))
        }
    }
}

public func makeFeatureFlagMiddleware(
    dependencies: ShoppingDependencies
) -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        next(action)

        guard case .featureFlags(.loadRequested) = action else { return }

        store.runTask(id: "feature-flags") {
            let snapshot = await dependencies.featureFlagService.fetchSnapshot()
            await store.dispatch(.featureFlags(.loaded(snapshot, Date())))
        }
    }
}

// MARK: - Analytics Middleware (Mock)

public let analyticsMiddleware: Middleware<ShoppingState, ShoppingAction> = { _, action, next in
    next(action)

    switch action {
    case .cart(.add(let product)):
        print("📊 [Analytics] User added \(product.name) to cart.")

    case .navigation(let navAction):
        switch navAction {
        case .push(let route):
            print("📊 [Analytics] User navigated to \(route).")
        default:
            break
        }

    default:
        break
    }
}
