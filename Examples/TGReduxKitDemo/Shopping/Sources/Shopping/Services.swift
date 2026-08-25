import Foundation
import TGReduxKit

// MARK: - Service protocols (Sendable — capture in Middleware / Effect factories)

public protocol ProductSearching: Sendable {
    func searchProducts(query: String, in products: [Product]) async -> [Product]
}

public protocol FeatureFlagFetching: Sendable {
    func fetchSnapshot() async -> FeatureFlagSnapshot
}

// MARK: - Live implementations

public struct LiveProductSearchService: ProductSearching {
    public init() {}

    public func searchProducts(query: String, in products: [Product]) async -> [Product] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return products }
        return products.filter { product in
            product.name.localizedCaseInsensitiveContains(normalizedQuery)
                || product.description.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

public actor LiveFeatureFlagService: FeatureFlagFetching {
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
        try? await Task.sleep(for: .milliseconds(500))
        return snapshot
    }
}

// MARK: - Effect cancellation IDs

public enum ShoppingEffectID {
    public static let catalogSearch: CancellationID = "catalog-search"
    public static let featureFlags: CancellationID = "feature-flags"
    public static let asyncLab: CancellationID = "async-lab"
}
