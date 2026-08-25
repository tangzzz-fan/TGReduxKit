import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

// MARK: - Product List

struct ProductListView: View {
    @Environment(Store<ShoppingState, ShoppingAction>.self) private var store

    var body: some View {
        List {
            Section {
                FeatureFlagStatusCard()

                TextField(
                    "Search products",
                    text: store.binding(
                        get: { $0.catalog.searchQuery },
                        send: { .catalog(.searchQueryChanged($0)) }
                    )
                )

                if store.state.catalog.isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.state.catalog.showsFreeShippingBanner {
                Section {
                    ProductBannerView(
                        title: "Free Shipping Active",
                        subtitle: "This banner is driven by catalog presentation state updated from remote flags."
                    )
                }
            }

            Section("Products") {
                if store.state.catalog.visibleProducts.isEmpty {
                    ContentUnavailableView(
                        "No Products",
                        systemImage: "shippingbox",
                        description: Text("Adjust search or refresh feature flags.")
                    )
                }

                ForEach(store.state.catalog.visibleProducts) { product in
                    Button {
                        store.dispatch(.navigation(.push(.detail(product.id))))
                    } label: {
                        ProductRowView(
                            product: product,
                            showsRecommendedBadge: store.state.catalog.showsRecommendedBadge
                        )
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

                if store.state.catalog.showsFreeShippingBanner {
                    ProductBannerView(
                        title: "Free Shipping Eligible",
                        subtitle: "The detail screen uses derived shopping state instead of reading the flag snapshot directly."
                    )
                    .padding(.horizontal)
                }

                Spacer()

                if store.state.isExpressCheckoutAvailable {
                    PrimaryActionButton(title: "Express Checkout") {
                        store.dispatch(.cart(.add(product)))
                        store.dispatch(.navigation(.push(.cart)))
                    }
                    .padding(.horizontal)
                }

                PrimaryActionButton(title: "Add to Cart") {
                    store.dispatch(.cart(.add(product)))
                }
                .padding(.horizontal)
                .padding(.bottom)
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
    @Environment(Store<ShoppingState, ShoppingAction>.self) private var store

    var body: some View {
        List {
            ForEach(store.state.cart.items) { item in
                HStack {
                    Text(item.product.name)
                    Spacer()
                    Text("x\(item.quantity)")
                    Text("$\(item.product.price * Decimal(item.quantity))")
                }
            }
            .onDelete { indexSet in
                store.dispatch(.cart(.remove(indexSet)))
            }

            if !store.state.cart.items.isEmpty {
                Section {
                    HStack {
                        Text("Total")
                            .bold()
                        Spacer()
                        Text("$\(store.state.cart.totalPrice)")
                            .bold()
                    }
                }
            }
        }
        .navigationTitle("Cart")
    }
}

struct FeatureFlagStatusCard: View {
    @Environment(Store<ShoppingState, ShoppingAction>.self) private var store

    private var enabledFlags: [String] {
        let snapshot = store.state.featureFlags.snapshot
        return [
            snapshot.isExpressCheckoutEnabled ? "Express Checkout" : nil,
            snapshot.showsFreeShippingBanner ? "Free Shipping Banner" : nil,
            snapshot.showsRecommendedBadge ? "Recommended Badge" : nil,
            snapshot.hidesBudgetProducts ? "Premium Catalog" : nil
        ].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remote Feature Flags")
                        .font(.headline)
                    Text(store.state.featureFlags.lastSource?.rawValue ?? "Waiting for first load")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Refresh") {
                    store.dispatch(.featureFlags(.loadRequested(.manualRefresh)))
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.state.featureFlags.isLoading)
            }

            if store.state.featureFlags.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Fetching remote configuration...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let lastUpdated = store.state.featureFlags.lastUpdated {
                Text("Last updated at \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if enabledFlags.isEmpty {
                        FeatureFlagChip(title: "All Optional Flags Disabled")
                    } else {
                        ForEach(enabledFlags, id: \.self) { flag in
                            FeatureFlagChip(title: flag)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct FeatureFlagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.12))
            .foregroundStyle(.blue)
            .clipShape(Capsule())
    }
}

struct ProductBannerView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct ProductRowView: View {
    let product: Product
    let showsRecommendedBadge: Bool

    var body: some View {
        HStack {
            Image(systemName: product.imageName)
                .font(.title)
                .frame(width: 50)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(product.name)
                        .font(.headline)

                    if showsRecommendedBadge {
                        FeatureFlagChip(title: "Recommended")
                    }
                }

                Text("$\(product.price)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.gray)
        }
    }
}

struct PrimaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
