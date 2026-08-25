import Foundation
import TGReduxKit

/// Stable cancellation IDs for shopping effects (latest-wins per id).
public enum ShoppingEffectID {
    public static let catalogSearch: CancellationID = "catalog-search"
    public static let featureFlags: CancellationID = "feature-flags"
}

/// Effect builders; services come from `DependencyContext`.
public enum ShoppingEffects {
    public static func searchCatalog(
        query: String,
        in products: [Product],
        search: @escaping @Sendable (String, [Product]) async -> [Product]
    ) -> Effect<CatalogAction> {
        .run(id: ShoppingEffectID.catalogSearch) {
            let results = await search(query, products)
            return .searchCompleted(query, results)
        }
        .debounce(for: .milliseconds(300))
    }

    public static func loadFeatureFlags(
        fetch: @escaping @Sendable () async -> FeatureFlagSnapshot,
        now: @escaping @Sendable () -> Date
    ) -> Effect<FeatureFlagsAction> {
        .run(id: ShoppingEffectID.featureFlags) {
            let snapshot = await fetch()
            return .loaded(snapshot, now())
        }
    }
}
