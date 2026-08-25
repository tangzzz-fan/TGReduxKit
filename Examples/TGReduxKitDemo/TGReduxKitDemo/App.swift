import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

public struct ShoppingAppView: View {
    @SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>

    public init(
        reducer: @escaping Reducer<ShoppingState, ShoppingAction> = shoppingReducer,
        middlewares: [Middleware<ShoppingState, ShoppingAction>] = makeShoppingMiddlewares()
    ) {
        _store = SwiftUI.State(
            initialValue: Store(
                initialState: ShoppingState(),
                reducer: reducer,
                middlewares: middlewares
            )
        )
    }

    public var body: some View {
        TGNavigationStack(
            state: store.state.navigation,
            dispatch: { store.dispatch(.navigation($0)) }
        ) {
            ProductListView()
        } destination: { route in
            switch route {
            case .list:
                ProductListView()
            case .detail(let id):
                ProductDetailView(productID: id)
            case .cart:
                CartView()
            }
        }
        .onOpenURL { url in
            store.dispatch(.handleDeepLink(url))
        }
        .task {
            store.dispatch(.featureFlags(.loadRequested(.launch)))
        }
        .provideStore(store)
    }
}

#Preview {
    ShoppingAppView()
}
