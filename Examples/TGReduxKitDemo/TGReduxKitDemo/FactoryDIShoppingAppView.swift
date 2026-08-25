import SwiftUI
import FactoryKit
import TGReduxKit
import Shopping

// MARK: - B) Factory-backed Composition Root

/// Resolve services from `Factory` / `FactoryKit`, then still call the same Middleware factories.
/// Do **not** `@Injected` into Reducer or put `Container` on `Store`.
public struct FactoryDIShoppingAppView: View {
    @SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>

    /// Uses `Container.shared` registrations (`Container+Shopping.swift`).
    public init(container: Container = .shared) {
        _store = SwiftUI.State(
            initialValue: ShoppingStoreBootstrap.makeStore(
                productSearch: container.productSearch(),
                featureFlags: container.featureFlags(),
                now: container.now()
            )
        )
    }

    public var body: some View {
        ShoppingRootHost(store: store)
    }
}

#Preview("Factory / Live") {
    FactoryDIShoppingAppView()
}

#Preview("Factory / Preview override") {
    let _ = Container.shared.featureFlags.register { PreviewFeatureFlagService() }
    return FactoryDIShoppingAppView()
}
