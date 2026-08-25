import Foundation
import FactoryKit
import Shopping

/// App-layer Factory registrations.
/// Shopping domain stays free of Factory — only the Composition Root resolves here.
extension Container {
    var productSearch: Factory<any ProductSearching> {
        self { LiveProductSearchService() }
    }

    var featureFlags: Factory<any FeatureFlagFetching> {
        self { LiveFeatureFlagService() }
    }

    /// Clock / `now` as a Sendable closure factory (same role as a manual `now:` argument).
    var now: Factory<@Sendable () -> Date> {
        self { { Date() } }
    }
}
