import Foundation
import TGReduxKit

/// Live service closures captured by middleware factories.
public enum ShoppingServices {
    public static let searchProducts: @Sendable (String, [Product]) async -> [Product] = { query, products in
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return products }
        return products.filter { product in
            product.name.localizedCaseInsensitiveContains(normalizedQuery)
                || product.description.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    public static let fetchFeatureFlags: @Sendable () async -> FeatureFlagSnapshot = {
        await FeatureFlagVariants.next()
    }
}

private actor FeatureFlagVariants {
    private static let shared = FeatureFlagVariants()
    private var nextVariantIndex = 0

    static func next() async -> FeatureFlagSnapshot {
        await shared.fetch()
    }

    private func fetch() async -> FeatureFlagSnapshot {
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

public enum ShoppingEffectID {
    public static let catalogSearch: CancellationID = "catalog-search"
    public static let featureFlags: CancellationID = "feature-flags"
}
