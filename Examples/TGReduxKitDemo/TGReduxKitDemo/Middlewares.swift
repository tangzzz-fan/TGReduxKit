import Foundation
import TGReduxKit

// MARK: - Logging Middleware

public let loggingMiddleware: Middleware<ShoppingState, ShoppingAction> = actionLoggingMiddleware()

public protocol ProductSearchServicing: Sendable {
    func searchProducts(query: String, in products: [Product]) async -> [Product]
}

public struct LiveProductSearchService: ProductSearchServicing {
    public init() {}

    public func searchProducts(query: String, in products: [Product]) async -> [Product] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedQuery.isEmpty else {
            return products
        }

        return products.filter { product in
            product.name.localizedCaseInsensitiveContains(normalizedQuery)
            || product.description.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

public protocol FeatureFlagServicing: Sendable {
    func fetchSnapshot() async -> FeatureFlagSnapshot
}

public actor DemoFeatureFlagService: FeatureFlagServicing {
    private var nextVariantIndex = 0

    public init() {}

    public func fetchSnapshot() async -> FeatureFlagSnapshot {
        let variants = [
            FeatureFlagSnapshot(
                isExpressCheckoutEnabled: false,
                showsFreeShippingBanner: true,
                showsRecommendedBadge: true,
                hidesBudgetProducts: false
            ),
            FeatureFlagSnapshot(
                isExpressCheckoutEnabled: true,
                showsFreeShippingBanner: false,
                showsRecommendedBadge: true,
                hidesBudgetProducts: true
            )
        ]

        let snapshot = variants[nextVariantIndex % variants.count]
        nextVariantIndex += 1

        try? await Task.sleep(nanoseconds: 500_000_000)
        return snapshot
    }
}

public struct ShoppingDependencies: Sendable {
    public var productSearchService: any ProductSearchServicing
    public var featureFlagService: any FeatureFlagServicing

    public init(
        productSearchService: any ProductSearchServicing = LiveProductSearchService(),
        featureFlagService: any FeatureFlagServicing = DemoFeatureFlagService()
    ) {
        self.productSearchService = productSearchService
        self.featureFlagService = featureFlagService
    }
}

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

/// A middleware that simulates tracking specific actions to an analytics service.
public let analyticsMiddleware: Middleware<ShoppingState, ShoppingAction> = { _, action, next in
    next(action)

    switch action {
    case .cart(.add(let product)):
        print("📊 [Analytics] User added \(product.name) to cart.")

    case .navigation(let navAction):
        if case .push(let route) = navAction {
            print("📊 [Analytics] User navigated to \(route).")
        }

    default:
        break
    }
}
