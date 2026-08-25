import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

/// Demo shell: one `ObservableStore`; services live on `DependencyContext`.
public struct ShoppingAppView: View {
    @State private var store: ObservableStore<ShoppingState, ShoppingAction>

    public init() {
        _store = State(
            initialValue: ObservableStore(
                initialState: ShoppingState(),
                reducer: shoppingReducer
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
