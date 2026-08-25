import Foundation
import TGReduxKit

/// Stable cancellation IDs for shopping effects (latest-wins per id).
public enum ShoppingEffectID {
    public static let catalogSearch: CancellationID = "catalog-search"
    public static let featureFlags: CancellationID = "feature-flags"
}

/// Effect builders. Services are `@Sendable` closures captured by the reducer factory.
public enum ShoppingEffects {
    public static func searchCatalog(
        query: String,
        in products: [Product],
        search: @escaping @Sendable (String, [Product]) async -> [Product]
    ) -> Effect<CatalogAction> {
        .run(id: ShoppingEffectID.catalogSearch) { send in
            let results = await search(query, products)
            await send(.searchCompleted(query, results))
        }
        .debounce(for: .milliseconds(300))
    }

    public static func loadFeatureFlags(
        fetch: @escaping @Sendable () async -> FeatureFlagSnapshot,
        now: @escaping @Sendable () -> Date
    ) -> Effect<FeatureFlagsAction> {
        .run(id: ShoppingEffectID.featureFlags) { send in
            let snapshot = await fetch()
            await send(.loaded(snapshot, now()))
        }
    }
}
