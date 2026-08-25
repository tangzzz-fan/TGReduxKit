import Foundation
import TGReduxKit
import TGNavigationStack

// MARK: - Pure reducers (Void)

public let shoppingReducer: Reducer<ShoppingState, ShoppingAction> = combineReducers(
    pullback(
        catalogReducer,
        state: \.catalog,
        action: ShoppingAction.catalog,
        extract: { if case .catalog(let a) = $0 { a } else { nil } }
    ),
    pullback(
        cartReducer,
        state: \.cart,
        action: ShoppingAction.cart,
        extract: { if case .cart(let a) = $0 { a } else { nil } }
    ),
    pullback(
        featureFlagsReducer,
        state: \.featureFlags,
        action: ShoppingAction.featureFlags,
        extract: { if case .featureFlags(let a) = $0 { a } else { nil } }
    ),
    pullback(
        asyncLabReducer,
        state: \.asyncLab,
        action: ShoppingAction.asyncLab,
        extract: { if case .asyncLab(let a) = $0 { a } else { nil } }
    ),
    crossCuttingReducer
)

private let catalogReducer: Reducer<CatalogState, CatalogAction> = { state, action in
    switch action {
    case .searchQueryChanged(let query):
        state.searchQuery = query
        state.isSearching = !query.isEmpty
        if query.isEmpty {
            state.isSearching = false
        }
    case .searchCompleted(let query, let products):
        guard query == state.searchQuery else { return }
        state.isSearching = false
        state.visibleProducts = products
    }
}

private let cartReducer: Reducer<CartState, CartAction> = { state, action in
    switch action {
    case .add(let product):
        if let index = state.items.firstIndex(where: { $0.product.id == product.id }) {
            state.items[index].quantity += 1
        } else {
            state.items.append(CartItem(product: product))
        }
    case .remove(let offsets):
        for index in offsets.sorted(by: >) {
            state.items.remove(at: index)
        }
    }
}

private let featureFlagsReducer: Reducer<FeatureFlagsState, FeatureFlagsAction> = { state, action in
    switch action {
    case .loadRequested(let source):
        state.isLoading = true
        state.lastSource = source
        state.lastError = nil
    case .loaded(let snapshot, let lastUpdated):
        state.snapshot = snapshot
        state.isLoading = false
        state.lastUpdated = lastUpdated
        state.lastError = nil
        state.simulateNextLoadFailure = false
    case .loadFailed(let message):
        state.isLoading = false
        state.lastError = message
        state.simulateNextLoadFailure = false
    case .setSimulateNextLoadFailure(let value):
        state.simulateNextLoadFailure = value
    }
}

private let asyncLabReducer: Reducer<AsyncLabState, AsyncLabAction> = { state, action in
    switch action {
    case .setRespectCancellation(let value):
        state.respectCancellation = value
    case .startLongJob:
        state.isRunning = true
        state.progress = 0
        state.outcome = .running
        state.detail = state.respectCancellation
            ? "Running with Task.isCancelled checks…"
            : "Running WITHOUT checks (failure demo)…"
    case .cancelJob:
        // Sync UI immediately; Effect.cancel stops the Task.
        // If the Effect ignores Task.isCancelled, `.leakedAfterCancel` may still overwrite this.
        if state.isRunning {
            state.isRunning = false
            state.outcome = .cancelledCleanly
            state.detail = "Cancel requested — waiting to see if Effect leaks…"
        }
    case .progress(let step):
        // Ignore progress after a clean cancel (good path); leak path keeps isRunning false but still updates.
        state.progress = step
        if state.outcome == .running {
            state.detail = "Step \(step)/\(state.totalSteps)"
        } else if state.outcome == .cancelledCleanly || state.outcome == .staleLeak {
            state.detail = "Stale progress \(step)/\(state.totalSteps) after cancel"
        }
    case .finished(let message):
        state.isRunning = false
        state.outcome = .completed
        state.detail = message
    case .cancelledCleanly:
        state.isRunning = false
        state.outcome = .cancelledCleanly
        state.detail = "Cancelled cleanly — no stale follow-up."
    case .leakedAfterCancel(let message):
        state.isRunning = false
        state.outcome = .staleLeak
        state.detail = message
    }
}

private let crossCuttingReducer: Reducer<ShoppingState, ShoppingAction> = { state, action in
    switch action {
    case .catalog(.searchCompleted(_, let products)):
        state.catalog.visibleProducts = applyFeatureFlags(
            to: products,
            flags: state.featureFlags.snapshot
        )

    case .catalog(.searchQueryChanged(let query)) where query.isEmpty:
        state.catalog.visibleProducts = visibleProducts(
            from: state.catalog.allProducts,
            matching: query,
            flags: state.featureFlags.snapshot
        )

    case .featureFlags(.loaded(let snapshot, _)):
        state.catalog.showsFreeShippingBanner = snapshot.showsFreeShippingBanner
        state.catalog.showsRecommendedBadge = snapshot.showsRecommendedBadge
        state.catalog.isPremiumCatalogOnly = snapshot.hidesBudgetProducts
        state.isExpressCheckoutAvailable = snapshot.isExpressCheckoutEnabled
        state.catalog.visibleProducts = visibleProducts(
            from: state.catalog.allProducts,
            matching: state.catalog.searchQuery,
            flags: snapshot
        )

    case .navigation(let navAction):
        navigationReducer(state: &state.navigation, action: navAction)

    case .handleDeepLink(let url):
        guard url.scheme == "tgshop",
              url.host == "product",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems,
              let idString = queryItems.first(where: { $0.name == "id" })?.value,
              let id = UUID(uuidString: idString),
              state.product(for: id) != nil
        else {
            return
        }
        navigationReducer(state: &state.navigation, action: .push(.detail(id)))

    default:
        break
    }
}

// MARK: - Middleware factories (DI at the door — capture deps, never inject into Store/Reducer)

/// Composition helper: build the middleware stack from explicit dependencies.
public func makeShoppingMiddlewares(
    dependencies: ShoppingDependencies = .live
) -> [Middleware<ShoppingState, ShoppingAction>] {
    [
        makeCatalogSearchMiddleware(productSearch: dependencies.productSearch),
        makeFeatureFlagsMiddleware(
            featureFlags: dependencies.featureFlags,
            now: dependencies.now
        ),
        makeAsyncLabMiddleware()
    ]
}

public func makeCatalogSearchMiddleware(
    productSearch: any ProductSearching
) -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        let base = next(action)
        guard case .catalog(.searchQueryChanged(let query)) = action else {
            return base
        }
        if query.isEmpty {
            // Cancel in-flight debounce/search when the field is cleared.
            return .merge(base, .cancel(id: ShoppingEffectID.catalogSearch))
        }
        let products = store.state.catalog.allProducts
        return .merge(
            base,
            .debounce(id: ShoppingEffectID.catalogSearch, delay: .milliseconds(300)) {
                let results = await productSearch.searchProducts(query: query, in: products)
                // After await: cancel may have fired — check again before returning.
                guard !Task.isCancelled else { return nil }
                return .catalog(.searchCompleted(query, results))
            }
        )
    }
}

public func makeFeatureFlagsMiddleware(
    featureFlags: any FeatureFlagFetching,
    now: @escaping @Sendable () -> Date
) -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        let base = next(action)
        guard case .featureFlags(.loadRequested) = action else {
            return base
        }
        let shouldFail = store.state.featureFlags.simulateNextLoadFailure
        return .merge(
            base,
            .task(id: ShoppingEffectID.featureFlags) {
                if shouldFail {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return nil }
                    return .featureFlags(.loadFailed("Simulated network failure (demo)"))
                }
                let snapshot = await featureFlags.fetchSnapshot()
                guard !Task.isCancelled else { return nil }
                return .featureFlags(.loaded(snapshot, now()))
            }
        )
    }
}

/// Long-job lab: `CancellationID` cancels the Task; **you** must still honor `Task.isCancelled`.
///
/// Checking in a loop is necessary but not enough by itself — see README / EFFECT_GUIDE.
/// Failure mode: skip the check and `dispatch` mid-flight (bypasses Store’s final return-value guard).
public func makeAsyncLabMiddleware() -> Middleware<ShoppingState, ShoppingAction> {
    { store, action, next in
        let base = next(action)
        switch action {
        case .asyncLab(.startLongJob):
            let respect = store.state.asyncLab.respectCancellation
            let total = store.state.asyncLab.totalSteps
            let box = MainActorStoreBox(store)
            return .merge(
                base,
                .task(id: ShoppingEffectID.asyncLab) {
                    for step in 1...total {
                        try? await Task.sleep(for: .milliseconds(400))
                        if respect {
                            guard !Task.isCancelled else { return nil }
                            await box.dispatch(.asyncLab(.progress(step)))
                        } else {
                            // Failure demo: ignore cancellation; mid-loop dispatch still lands.
                            await box.dispatch(.asyncLab(.progress(step)))
                        }
                    }
                    if Task.isCancelled {
                        if respect { return nil }
                        await box.dispatch(
                            .asyncLab(
                                .leakedAfterCancel(
                                    "Leak: checked nothing — kept dispatching after cancel (竞态/脏写)."
                                )
                            )
                        )
                        return nil
                    }
                    return .asyncLab(.finished("Long job finished cleanly."))
                }
            )

        case .asyncLab(.cancelJob):
            return .merge(base, .cancel(id: ShoppingEffectID.asyncLab))

        default:
            return base
        }
    }
}

/// Bridges MainActor `StoreType` into `@Sendable` Effect bodies (demo only).
private struct MainActorStoreBox: @unchecked Sendable {
    private let store: any StoreType<ShoppingState, ShoppingAction>

    init(_ store: any StoreType<ShoppingState, ShoppingAction>) {
        self.store = store
    }

    func dispatch(_ action: ShoppingAction) async {
        await MainActor.run {
            store.dispatch(action)
        }
    }
}
