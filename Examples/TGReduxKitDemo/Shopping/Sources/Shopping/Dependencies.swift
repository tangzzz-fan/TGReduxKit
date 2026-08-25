import Foundation
import TGReduxKit

// MARK: - Protocols (Sendable — safe to capture in Middleware / Effect)

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

// MARK: - Composition bag (values only — not a DI container)

/// Dependencies assembled at the Composition Root and passed into middleware factories.
public struct ShoppingDependencies: Sendable {
    public var productSearch: any ProductSearching
    public var featureFlags: any FeatureFlagFetching
    public var now: @Sendable () -> Date

    public init(
        productSearch: any ProductSearching = LiveProductSearchService(),
        featureFlags: any FeatureFlagFetching = LiveFeatureFlagService(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.productSearch = productSearch
        self.featureFlags = featureFlags
        self.now = now
    }

    public static let live = ShoppingDependencies()
}

public enum ShoppingEffectID {
    public static let catalogSearch: CancellationID = "catalog-search"
    public static let featureFlags: CancellationID = "feature-flags"
}
