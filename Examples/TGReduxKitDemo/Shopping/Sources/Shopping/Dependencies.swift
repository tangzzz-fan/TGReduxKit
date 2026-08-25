import Foundation
import TGReduxKit

// MARK: - Dependency keys (function values — no protocol bag)

private enum ProductSearchKey: DependencyKey {
    static let liveValue: @Sendable (String, [Product]) async -> [Product] = { query, products in
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return products }
        return products.filter { product in
            product.name.localizedCaseInsensitiveContains(normalizedQuery)
                || product.description.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }
}

private enum FeatureFlagsKey: DependencyKey {
    static let liveValue: @Sendable () async -> FeatureFlagSnapshot = {
        await FeatureFlagVariants.next()
    }
}

/// Demo feature-flag remote stand-in (cycles two snapshots).
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

extension DependencyContext {
    public var searchProducts: @Sendable (String, [Product]) async -> [Product] {
        get { self[ProductSearchKey.self] }
        set { self[ProductSearchKey.self] = newValue }
    }

    public var fetchFeatureFlags: @Sendable () async -> FeatureFlagSnapshot {
        get { self[FeatureFlagsKey.self] }
        set { self[FeatureFlagsKey.self] = newValue }
    }
}
