import Foundation

// MARK: - Services

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
