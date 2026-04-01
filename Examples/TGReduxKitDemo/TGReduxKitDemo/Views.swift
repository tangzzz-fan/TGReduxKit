import SwiftUI
import TGReduxKit

// MARK: - Product List

struct ProductListView: View {
    @Environment(Store<ShoppingState, ShoppingAction>.self) private var store
    @Environment(ScopedStore<CatalogState, CatalogAction>.self) private var catalogStore

    var body: some View {
        List {
            Section {
                TextField(
                    "Search products",
                    text: catalogStore.binding(
                        get: \.searchQuery,
                        send: CatalogAction.searchQueryChanged
                    )
                )

                if catalogStore.state.isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(catalogStore.state.visibleProducts) { product in
                    Button {
                        store.dispatch(.navigation(.push(.detail(product.id))))
                    } label: {
                        HStack {
                            Image(systemName: product.imageName)
                                .font(.title)
                                .frame(width: 50)
                            VStack(alignment: .leading) {
                                Text(product.name)
                                    .font(.headline)
                                Text("$\(product.price)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.gray)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Products")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.dispatch(.navigation(.push(.cart)))
                } label: {
                    HStack {
                        Image(systemName: "cart")
                        Text("\(store.state.cart.totalQuantity)")
                    }
                }
            }
        }
    }
}

// MARK: - Product Detail

struct ProductDetailView: View {
    let productID: UUID
    @Environment(Store<ShoppingState, ShoppingAction>.self) private var store

    var product: Product? {
        store.state.product(for: productID)
    }

    var body: some View {
        if let product = product {
            VStack(spacing: 20) {
                Image(systemName: product.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
                    .padding()
                
                Text(product.name)
                    .font(.largeTitle)
                    .bold()
                
                Text("$\(product.price)")
                    .font(.title)
                    .foregroundStyle(.secondary)
                
                Text(product.description)
                    .padding()
                
                Spacer()

                Button {
                    store.dispatch(.cart(.add(product)))
                } label: {
                    Text("Add to Cart")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
            }
            .navigationTitle(product.name)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.dispatch(.navigation(.push(.cart)))
                    } label: {
                        HStack {
                            Image(systemName: "cart")
                            Text("\(store.state.cart.totalQuantity)")
                        }
                    }
                }
            }
        } else {
            Text("Product not found")
        }
    }
}

// MARK: - Cart View

struct CartView: View {
    @Environment(ScopedStore<CartState, CartAction>.self) private var store

    var body: some View {
        List {
            ForEach(store.state.items) { item in
                HStack {
                    Text(item.product.name)
                    Spacer()
                    Text("x\(item.quantity)")
                    Text("$\(item.product.price * Decimal(item.quantity))")
                }
            }
            .onDelete { indexSet in
                store.dispatch(.remove(indexSet))
            }

            if !store.state.items.isEmpty {
                Section {
                    HStack {
                        Text("Total")
                            .bold()
                        Spacer()
                        Text("$\(store.state.totalPrice)")
                            .bold()
                    }
                }
            }
        }
        .navigationTitle("Cart")
    }
}
