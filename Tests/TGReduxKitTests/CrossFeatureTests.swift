import Testing
import Foundation
@testable import TGReduxKit

/// Tests covering the three cross-Feature communication patterns
/// documented in README「跨 Feature 通信」.
struct CrossFeatureTests {
    // MARK: - Simulated multi-Feature state

    struct CatalogState: Equatable {
        var products: [String] = []
        var lastAddedProductName: String?
    }

    struct CartState: Equatable {
        var items: [String] = []
    }

    struct RecommendationsState: Equatable {
        var lastProductID: String?
        var suggestions: [String] = []
    }

    struct AppState: Equatable {
        var catalog = CatalogState()
        var cart = CartState()
        var recommendations = RecommendationsState()
    }

    enum AppAction: Equatable {
        case catalog(CatalogAction)
        case cart(CartAction)
        case recommendations(RecommendationsAction)
        // Explicit cross-Feature coordination action (Pattern 3)
        case cartDidUpdate(addedProduct: String)
    }

    enum CatalogAction: Equatable {
        case addProduct(String)
    }

    enum CartAction: Equatable {
        case add(String)
        case remove(String)
    }

    enum RecommendationsAction: Equatable {
        case refresh(basedOn: String)
        case loaded([String])
    }

    // MARK: - Pattern 1: Parent-level middleware relay

    @MainActor
    @Test func testCrossFeatureMiddlewareRelaysCartAddToRecommendations() async throws {
        actor Recorder {
            var received: [String] = []
            func append(_ s: String) { received.append(s) }
        }

        let recorder = Recorder()

        // This cross-feature middleware listens for cart.add and triggers recommendations
        let relayMiddleware: Middleware<AppState, AppAction> = { store, action, next in
            next(action)

            if case .cart(.add(let productName)) = action {
                // Feature A (cart) event → triggers Feature B (recommendations) async effect
                store.runTask(id: "refresh-recs") {
                    await recorder.append("recommendations-refreshed-for-\(productName)")
                    // In real code this would call a recommendation service
                    await store.dispatch(.recommendations(.loaded(["Related to \(productName)"])))
                }
            }
        }

        let appReducer: Reducer<AppState, AppAction> = { state, action in
            switch action {
            case .catalog(.addProduct(let name)):
                state.catalog.products.append(name)
            case .cart(.add(let name)):
                state.cart.items.append(name)
            case .cart(.remove(let name)):
                state.cart.items.removeAll { $0 == name }
            case .recommendations(.loaded(let suggestions)):
                state.recommendations.suggestions = suggestions
            default:
                break
            }
        }

        let store = Store(
            initialState: AppState(),
            reducer: appReducer,
            middlewares: [relayMiddleware]
        )

        // Feature A: add to cart
        store.dispatch(.cart(.add("Widget")))

        // Cart state updated immediately
        #expect(store.state.cart.items == ["Widget"])

        // Wait for relay to trigger recommendation refresh
        try await Task.sleep(nanoseconds: 100_000_000)

        // Feature B received the cross-cutting update
        #expect(store.state.recommendations.suggestions == ["Related to Widget"])

        let events = await recorder.received
        #expect(events.first == "recommendations-refreshed-for-Widget")
    }

    // MARK: - Pattern 2: Reducer inline coordination

    @MainActor
    @Test func testReducerInlineCrossFeatureSyncUpdate() throws {
        // This reducer directly updates Feature B when Feature A changes
        let coordinatedReducer: Reducer<AppState, AppAction> = { state, action in
            switch action {
            case .catalog(.addProduct(let name)):
                state.catalog.products.append(name)
                // Inline cross-Feature sync update — Feature B tracks last added product
                state.catalog.lastAddedProductName = name
                state.recommendations.lastProductID = name

            case .cart(.add(let name)):
                state.cart.items.append(name)
                // Cart change → sync update to recommendations context
                state.recommendations.lastProductID = name

            case .recommendations(.loaded(let suggestions)):
                state.recommendations.suggestions = suggestions

            default:
                break
            }
        }

        let store = TestStore(initialState: AppState(), reducer: coordinatedReducer)

        // Catalog add → recommendations field updated inline
        store.send(.catalog(.addProduct("Gadget")))
        #expect(store.state.catalog.products == ["Gadget"])
        #expect(store.state.catalog.lastAddedProductName == "Gadget")
        #expect(store.state.recommendations.lastProductID == "Gadget")

        // Cart add → recommendations field updated inline
        store.send(.cart(.add("Widget")))
        #expect(store.state.cart.items == ["Widget"])
        #expect(store.state.recommendations.lastProductID == "Widget")

        // Verify full state consistency
        try store.assert { state in
            state.catalog.products.count == 1
                && state.cart.items.count == 1
                && state.recommendations.lastProductID == "Widget"
        }
    }

    // MARK: - Pattern 3: Explicit coordination action

    @MainActor
    @Test func testExplicitCoordinationActionPattern() throws {
        let reducer: Reducer<AppState, AppAction> = { state, action in
            switch action {
            case .catalog(.addProduct(let name)):
                state.catalog.products.append(name)

            case .cart(.add(let name)):
                state.cart.items.append(name)

            case .cartDidUpdate(let addedProduct):
                // Explicit cross-Feature coordination: the root reducer
                // wires Feature A's effect to Feature B's state
                state.recommendations.lastProductID = addedProduct

            case .recommendations(.loaded(let suggestions)):
                state.recommendations.suggestions = suggestions

            default:
                break
            }
        }

        let store = TestStore(initialState: AppState(), reducer: reducer)

        // Step 1: Feature A (cart) updates its own state
        store.send(.cart(.add("Widget")))
        #expect(store.state.cart.items == ["Widget"])

        // Step 2: Root dispatches explicit coordination action
        store.send(.cartDidUpdate(addedProduct: "Widget"))

        // Step 3: Feature B (recommendations) state is updated by the coordination action
        try store.assert(equals: AppState(
            catalog: CatalogState(),
            cart: CartState(items: ["Widget"]),
            recommendations: RecommendationsState(lastProductID: "Widget", suggestions: [])
        ))
    }

    @MainActor
    @Test func testExplicitCoordinationActionPreventsAccidentalCrossFeatureAccess() throws {
        struct FeatureAState: Equatable { var count = 0 }
        struct FeatureBState: Equatable { var message = "" }

        struct RootState: Equatable {
            var featureA = FeatureAState()
            var featureB = FeatureBState()
        }

        enum RootAction: Equatable {
            case a(FeatureAAction)
            case b(FeatureBAction)
            // Explicit — the only way to cross boundaries
            case featureADidChange(newCount: Int)
        }

        enum FeatureAAction: Equatable {
            case increment
        }

        enum FeatureBAction: Equatable {
            case setMessage(String)
        }

        let reducer: Reducer<RootState, RootAction> = { state, action in
            switch action {
            case .a(.increment):
                state.featureA.count += 1

            case .featureADidChange(let newCount):
                // Only explicit coordination actions can cross Feature boundaries
                state.featureB.message = "Feature A count is now \(newCount)"

            case .b(.setMessage(let msg)):
                state.featureB.message = msg
            }
        }

        let store = TestStore(initialState: RootState(), reducer: reducer)

        // Feature A can only dispatch its own actions via scoped store
        try store.send(.a(.increment), expect: RootState(featureA: FeatureAState(count: 1)))
        try store.send(.a(.increment), expect: RootState(featureA: FeatureAState(count: 2)))

        // Cross-Feature update goes through explicit coordination action
        store.send(.featureADidChange(newCount: 2))
        #expect(store.state.featureB.message == "Feature A count is now 2")

        // Feature B's own actions still work independently
        store.send(.b(.setMessage("independent")))
        #expect(store.state.featureB.message == "independent")
    }

    // MARK: - Patterns work together

    @MainActor
    @Test func testAllThreePatternsCoexist() async throws {
        // A reducer that combines Pattern 2 (inline sync) + Pattern 3 (explicit action)
        let reducer: Reducer<AppState, AppAction> = { state, action in
            switch action {
            case .catalog(.addProduct(let name)):
                state.catalog.products.append(name)
                state.catalog.lastAddedProductName = name          // Pattern 2: inline sync

            case .cart(.add(let name)):
                state.cart.items.append(name)

            case .cartDidUpdate(let addedProduct):
                state.recommendations.lastProductID = addedProduct // Pattern 3: explicit action

            case .recommendations(.loaded(let suggestions)):
                state.recommendations.suggestions = suggestions

            default:
                break
            }
        }

        // Pattern 1: parent-level middleware relay
        let relayMiddleware: Middleware<AppState, AppAction> = { store, action, next in
            next(action)

            if case .cart(.add(let productName)) = action {
                // Fire explicit coordination action
                store.dispatch(.cartDidUpdate(addedProduct: productName))

                // Trigger async effect for Feature B
                store.runTask(id: "load-recs") {
                    await store.dispatch(.recommendations(.loaded(["Also bought with \(productName)"])))
                }
            }
        }

        let store = Store(
            initialState: AppState(),
            reducer: reducer,
            middlewares: [relayMiddleware]
        )

        // Catalog add → Pattern 2 fires inline
        store.dispatch(.catalog(.addProduct("Phone")))
        #expect(store.state.catalog.lastAddedProductName == "Phone")

        // Cart add → Pattern 1 relay → Pattern 3 explicit action
        store.dispatch(.cart(.add("Phone")))
        #expect(store.state.cart.items == ["Phone"])

        // Pattern 3: explicit coordination action fired by middleware
        #expect(store.state.recommendations.lastProductID == "Phone")

        // Pattern 1: async recommendations loaded
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(store.state.recommendations.suggestions == ["Also bought with Phone"])
    }
}
