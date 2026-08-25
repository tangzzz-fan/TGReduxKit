import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

/// Demo shell: `@MainActor @Observable` `Store` is the SwiftUI root.
public struct ShoppingAppView: View {
    @State private var store: Store<ShoppingState, ShoppingAction>

    public init(reducer: Reducer<ShoppingState, ShoppingAction> = shoppingReducer) {
        _store = State(initialValue: Store(initialState: ShoppingState(), reducer: reducer))
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
