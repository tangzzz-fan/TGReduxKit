import SwiftUI
import TGReduxKit
import TGNavigationStack
import Shopping

// MARK: - 组装完成的 App 视图

/// 只接受**已经组装好的服务**。
///
/// 谁提供这些服务、从哪来，由 Composition Root（`DemoRootView`）决定 ——
/// 本视图不做任何解析，因此对 DI 框架零感知。
///
/// 注意 `now` **没有默认值**：默认参数是隐式依赖，会绕过"门口显式组装"的约束。
public struct ShoppingAppView: View {
    private let productSearch: any ProductSearching
    private let featureFlags: any FeatureFlagFetching
    private let now: @Sendable () -> Date

    /// 真正的 `Store` 在**首次出现时**才构建。
    ///
    /// 为什么不在 `init` 里写 `_store = State(initialValue: makeStore(...))`？
    /// `View` 是值类型：父视图每次重新求值都会重新调用 `init`。
    /// `State` 只保留**第一次**写入的值，其余全部丢弃 —— 于是 `makeStore`
    /// 会随父视图重绘次数线性执行，产出的 `Store` 被静默扔掉。
    ///
    /// 本 Demo 里 `Store.init` 无副作用，代价只是白分配几个对象；
    /// 但只要有一个 middleware 工厂带副作用（注册通知、起定时器、开文件句柄），
    /// 每帧就会泄漏一份。根因是把「持有」操作写进了「描述」阶段 ——
    /// `init` 是描述阶段（廉价、高频），对象图的构建属于持有阶段（昂贵、一次）。
    @SwiftUI.State private var store: Store<ShoppingState, ShoppingAction>?

    public init(
        productSearch: any ProductSearching,
        featureFlags: any FeatureFlagFetching,
        now: @escaping @Sendable () -> Date
    ) {
        self.productSearch = productSearch
        self.featureFlags = featureFlags
        self.now = now
    }

    public var body: some View {
        // 用 ZStack 而非 Group：容器身份稳定，`.onAppear` 不会随内容切换而重挂。
        ZStack {
            if let store {
                ShoppingRootHost(store: store)
            }
        }
        .onAppear {
            // onAppear 可能因导航进出而重复触发；Store 只应构建一次。
            guard store == nil else { return }
            store = ShoppingStoreBootstrap.makeStore(
                productSearch: productSearch,
                featureFlags: featureFlags,
                now: now
            )
        }
    }
}

// MARK: - 共享外壳（纯 UI）

struct ShoppingRootHost: View {
    @Bindable var store: Store<ShoppingState, ShoppingAction>

    var body: some View {
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

// MARK: - Previews

#Preview("显式实参 / Live") {
    ShoppingAppView(
        productSearch: LiveProductSearchService(),
        featureFlags: LiveFeatureFlagService(),
        now: { Date() }
    )
}

#Preview("显式实参 / 固定 flags") {
    ShoppingAppView(
        productSearch: LiveProductSearchService(),
        featureFlags: PreviewFeatureFlagService(),
        now: { Date() }
    )
}

struct PreviewFeatureFlagService: FeatureFlagFetching {
    func fetchSnapshot() async -> FeatureFlagSnapshot {
        FeatureFlagSnapshot(
            isExpressCheckoutEnabled: true,
            showsFreeShippingBanner: true,
            showsRecommendedBadge: true,
            hidesBudgetProducts: false
        )
    }
}
