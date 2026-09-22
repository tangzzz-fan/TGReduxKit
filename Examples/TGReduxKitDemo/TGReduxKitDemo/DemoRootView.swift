import SwiftUI
import FactoryKit
import Shopping

/// **全工程唯一接触 DI 容器的地方。**
///
/// 两种接线方式产出**同一个** `ShoppingAppView` —— 差异只在「服务从哪来」，
/// 不在架构。`makeStore` 的签名始终是唯一的编译期依赖契约；
/// 容器解析只发生在这里，不会渗透到 View、Store 或 Middleware。
struct DemoRootView: View {
    enum Wiring: String, CaseIterable, Identifiable {
        case explicit = "显式实参"
        case container = "Factory 容器解析"

        var id: String { rawValue }
    }

    @State private var wiring: Wiring?

    var body: some View {
        Group {
            if let wiring {
                switch wiring {
                case .explicit:
                    ShoppingAppView(
                        productSearch: LiveProductSearchService(),
                        featureFlags: LiveFeatureFlagService(),
                        now: { Date() }
                    )

                case .container:
                    ShoppingAppView(
                        productSearch: Container.shared.productSearch(),
                        featureFlags: Container.shared.featureFlags(),
                        now: Container.shared.now()
                    )
                }
            } else {
                NavigationStack {
                    List(Wiring.allCases) { item in
                        Button(item.rawValue) {
                            wiring = item
                        }
                    }
                    .navigationTitle("Composition Root")
                    .safeAreaInset(edge: .bottom) {
                        Text(
                            "两种接线都调用同一个 makeStore。Factory 只改变服务在门口如何被解析，不改变依赖契约。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                    }
                }
            }
        }
    }
}

#Preview("Factory 接线 / 预览覆盖") {
    // 覆盖方式是**换实参**，不是改全局容器 —— 因此不存在跨 Preview 污染。
    ShoppingAppView(
        productSearch: Container.shared.productSearch(),
        featureFlags: PreviewFeatureFlagService(),
        now: Container.shared.now()
    )
}
