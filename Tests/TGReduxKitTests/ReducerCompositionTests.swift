import Testing
import Foundation
@testable import TGReduxKit

struct ReducerCompositionTests {
    // MARK: - State & Action types

    struct CatalogState: Equatable {
        var products: [String] = []
        var searchQuery: String = ""
    }

    struct CartState: Equatable {
        var items: [String] = []
        var totalQuantity: Int = 0
    }

    struct AppState: Equatable {
        var catalog = CatalogState()
        var cart = CartState()
    }

    enum AppAction: Equatable {
        case catalog(CatalogAction)
        case cart(CartAction)
    }

    enum CatalogAction: Equatable {
        case addProduct(String)
        case search(String)
    }

    enum CartAction: Equatable {
        case add(String)
        case remove(String)
    }

    // Feature reducers
    let catalogReducer: Reducer<CatalogState, CatalogAction> = { state, action in
        switch action {
        case .addProduct(let name):
            state.products.append(name)
        case .search(let query):
            state.searchQuery = query
        }
    }

    let cartReducer: Reducer<CartState, CartAction> = { state, action in
        switch action {
        case .add(let name):
            state.items.append(name)
            state.totalQuantity += 1
        case .remove(let name):
            if let idx = state.items.firstIndex(of: name) {
                state.items.remove(at: idx)
                state.totalQuantity -= 1
            }
        }
    }

    // MARK: - combineReducers basics

    @MainActor
    @Test func testCombineReducersExecutesAllInOrder() {
        let combined: Reducer<AppState, AppAction> = combineReducers(
            pullback(catalogReducer,
                state: \.catalog,
                extract: { (parent: AppAction) in if case .catalog(let a) = parent { a } else { nil } }
            ),
            pullback(cartReducer,
                state: \.cart,
                extract: { (parent: AppAction) in if case .cart(let a) = parent { a } else { nil } }
            )
        )

        let store = TestStore(initialState: AppState(), reducer: combined)

        // Catalog action -> only catalog reducer should respond
        store.send(.catalog(.addProduct("Widget")))
        #expect(store.state.catalog.products == ["Widget"])
        #expect(store.state.cart.items.isEmpty)

        // Cart action -> only cart reducer should respond
        store.send(.cart(.add("Widget")))
        #expect(store.state.catalog.products == ["Widget"])
        #expect(store.state.cart.items == ["Widget"])
        #expect(store.state.cart.totalQuantity == 1)
    }

    @MainActor
    @Test func testCombineReducersWithMultipleActions() {
        let combined: Reducer<AppState, AppAction> = combineReducers(
            pullback(catalogReducer,
                state: \.catalog,
                extract: { (parent: AppAction) in if case .catalog(let a) = parent { a } else { nil } }
            ),
            pullback(cartReducer,
                state: \.cart,
                extract: { (parent: AppAction) in if case .cart(let a) = parent { a } else { nil } }
            )
        )

        let store = TestStore(initialState: AppState(), reducer: combined)

        // Interleave actions
        store.send(.catalog(.addProduct("A")))
        store.send(.cart(.add("B")))
        store.send(.catalog(.addProduct("C")))
        store.send(.cart(.add("D")))
        store.send(.cart(.remove("D")))

        #expect(store.state.catalog.products == ["A", "C"])
        #expect(store.state.cart.items == ["B"])
        #expect(store.state.cart.totalQuantity == 1)
    }

    // MARK: - pullback isolation

    @MainActor
    @Test func testPullbackOnlyRunsWhenExtractReturnsNonNil() {
        let lifted: Reducer<AppState, AppAction> = pullback(catalogReducer,
            state: \.catalog,
            extract: { (parent: AppAction) in if case .catalog(let a) = parent { a } else { nil } }
        )

        let store = TestStore(initialState: AppState(), reducer: lifted)

        // This should be ignored -> extract returns nil
        store.send(.cart(.add("ShouldNotAppear")))
        #expect(store.state.catalog.products.isEmpty)
        #expect(store.state.cart.items.isEmpty)  // Cart state untouched

        // This should work -> extract returns child action
        store.send(.catalog(.addProduct("Widget")))
        #expect(store.state.catalog.products == ["Widget"])
    }

    @MainActor
    @Test func testPullbackPreservesRestOfParentState() {
        let initialState = AppState(
            catalog: CatalogState(products: ["Existing"], searchQuery: "hello"),
            cart: CartState(items: ["PreExisting"], totalQuantity: 5)
        )

        let lifted: Reducer<AppState, AppAction> = pullback(catalogReducer,
            state: \.catalog,
            extract: { (parent: AppAction) in if case .catalog(let a) = parent { a } else { nil } }
        )

        let store = TestStore(initialState: initialState, reducer: lifted)

        store.send(.catalog(.addProduct("New")))

        // Catalog updated
        #expect(store.state.catalog.products == ["Existing", "New"])
        // Cart untouched
        #expect(store.state.cart.items == ["PreExisting"])
        #expect(store.state.cart.totalQuantity == 5)
    }

    // MARK: - Deep nesting

    @MainActor
    @Test func testDeeplyNestedPullback() {
        struct DeepState: Equatable {
            var app = AppState()
            var message = ""
        }

        enum DeepAction: Equatable {
            case app(AppAction)
            case setMessage(String)
        }

        let catalogPullback: Reducer<AppState, AppAction> = pullback(catalogReducer,
            state: \.catalog,
            extract: { (parent: AppAction) in if case .catalog(let a) = parent { a } else { nil } }
        )

        let deepReducer: Reducer<DeepState, DeepAction> = combineReducers(
            pullback(catalogPullback,
                state: \.app,
                extract: { (parent: DeepAction) in if case .app(let a) = parent { a } else { nil } }
            )
        )

        var state = DeepState()
        deepReducer(&state, .app(.catalog(.addProduct("Deep"))))
        #expect(state.app.catalog.products == ["Deep"])

        deepReducer(&state, .app(.catalog(.search("test"))))
        #expect(state.app.catalog.searchQuery == "test")

        // Unrelated actions are ignored
        deepReducer(&state, .setMessage("ignored"))
        #expect(state.app.catalog.products == ["Deep"])
    }

    // MARK: - combineReducers with single reducer

    @MainActor
    @Test func testCombineReducersWithSingleReducer() {
        let single: Reducer<AppState, AppAction> = combineReducers(
            pullback(catalogReducer,
                state: \.catalog,
                extract: { (parent: AppAction) in if case .catalog(let a) = parent { a } else { nil } }
            )
        )

        let store = TestStore(initialState: AppState(), reducer: single)

        store.send(.catalog(.addProduct("X")))
        #expect(store.state.catalog.products == ["X"])
    }

    @MainActor
    @Test func testCombineReducersWithEmptyList() {
        let empty: Reducer<AppState, AppAction> = combineReducers()

        let store = TestStore(initialState: AppState(), reducer: empty)

        store.send(.catalog(.addProduct("X")))
        // Nothing should change — no reducers registered
        #expect(store.state.catalog.products.isEmpty)
    }

    // MARK: - Demo shopping state equivalent

    @MainActor
    @Test func testShoppingAppCombinePattern() {
        struct ShoppingState: Equatable {
            var catalog = CatalogState()
            var cart = CartState()
        }

        // Same pattern as the Demo app but using combineReducers
        let shoppingReducer: Reducer<ShoppingState, AppAction> = combineReducers(
            pullback(catalogReducer,
                state: \.catalog,
                extract: { (parent: AppAction) in if case .catalog(let a) = parent { a } else { nil } }
            ),
            pullback(cartReducer,
                state: \.cart,
                extract: { (parent: AppAction) in if case .cart(let a) = parent { a } else { nil } }
            )
        )

        let store = TestStore(initialState: ShoppingState(), reducer: shoppingReducer)

        // Full shopping flow
        store.send(.catalog(.search("Phone")))
        store.send(.catalog(.addProduct("iPhone")))
        store.send(.catalog(.addProduct("MacBook")))

        #expect(store.state.catalog.products == ["iPhone", "MacBook"])
        #expect(store.state.catalog.searchQuery == "Phone")

        store.send(.cart(.add("iPhone")))
        store.send(.cart(.add("MacBook")))

        #expect(store.state.cart.items == ["iPhone", "MacBook"])
        #expect(store.state.cart.totalQuantity == 2)

        store.send(.cart(.remove("iPhone")))
        #expect(store.state.cart.items == ["MacBook"])
        #expect(store.state.cart.totalQuantity == 1)
    }

    // MARK: - Multiple extract patterns on same action

    @MainActor
    @Test func testMultiplePullbacksWithDifferentExtractPatterns() {
        enum FlatAction: Equatable {
            case addToCatalog(String)
            case removeFromCatalog(String)
            case addToCart(String)
            case clearAll
        }

        struct FlatState: Equatable {
            var catalog: CatalogState = .init()
            var cart: CartState = .init()
        }

        let catalogReducer: Reducer<FlatState, FlatAction> = { state, action in
            switch action {
            case .addToCatalog(let name):
                state.catalog.products.append(name)
            case .removeFromCatalog(let name):
                state.catalog.products.removeAll { $0 == name }
            default:
                break
            }
        }

        let cartReducer: Reducer<FlatState, FlatAction> = { state, action in
            switch action {
            case .addToCart(let name):
                state.cart.items.append(name)
                state.cart.totalQuantity += 1
            default:
                break
            }
        }

        let combined = combineReducers(catalogReducer, cartReducer)

        let store = TestStore(initialState: FlatState(), reducer: combined)

        store.send(.addToCatalog("A"))
        store.send(.addToCatalog("B"))
        store.send(.addToCart("A"))

        #expect(store.state.catalog.products == ["A", "B"])
        #expect(store.state.cart.items == ["A"])
        #expect(store.state.cart.totalQuantity == 1)

        // clearAll is ignored by both reducers
        store.send(.clearAll)
        #expect(store.state.catalog.products == ["A", "B"])
        #expect(store.state.cart.totalQuantity == 1)
    }

    // MARK: - Navigation reducer composition

    @MainActor
    @Test func testNavigationReducerWithCombineReducers() {
        struct NavState: Equatable {
            var catalog = CatalogState()
            var path: [String] = []
        }

        enum NavAction: Equatable {
            case catalog(CatalogAction)
            case push(String)
            case pop
        }

        let catalogReducer: Reducer<NavState, NavAction> = { state, action in
            if case .catalog(let a) = action {
                switch a {
                case .addProduct(let name):
                    state.catalog.products.append(name)
                case .search(let q):
                    state.catalog.searchQuery = q
                }
            }
        }

        let navReducer: Reducer<NavState, NavAction> = { state, action in
            switch action {
            case .push(let page):
                state.path.append(page)
            case .pop:
                if !state.path.isEmpty { state.path.removeLast() }
            default:
                break
            }
        }

        let combined = combineReducers(catalogReducer, navReducer)

        let store = TestStore(initialState: NavState(), reducer: combined)

        store.send(.catalog(.addProduct("Item")))
        store.send(.push("Detail"))
        store.send(.push("Cart"))

        #expect(store.state.catalog.products == ["Item"])
        #expect(store.state.path == ["Detail", "Cart"])

        store.send(.pop)
        #expect(store.state.path == ["Detail"])
    }
}
