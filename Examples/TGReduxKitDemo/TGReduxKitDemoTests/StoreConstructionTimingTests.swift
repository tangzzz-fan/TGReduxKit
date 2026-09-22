//
//  StoreConstructionTimingTests.swift
//  TGReduxKitDemoTests
//

import Foundation
import Testing
@testable import TGReduxKitDemo
import Shopping

/// 钉住 `ShoppingAppView` 的**构建时机**契约。
///
/// 背景：SwiftUI `View` 是值类型，父视图每次重新求值都会重新调用 `init`。
/// 若在 `init` 里 `State(initialValue: makeStore(...))`，则每次重绘都会白构建一个
/// `Store` 再被 `State` 静默丢弃（`State` 只保留第一次写入）。
///
/// **为什么这需要测试**：这个回归是**静默**的 —— 界面行为完全正确，只是每次重绘
/// 多分配一个 Store。没有断言就没人会发现。
///
/// **为什么不需要托管视图**：另一条失败路径（删掉 `.onAppear`）会导致 Store 永不构建、
/// 界面永久空白 —— 那是**响亮**的失败，跑一次 Demo 就能看到，不需要测试兜底。
/// 真正需要钉住的只有「描述阶段不得有副作用」这一条。
@MainActor
struct StoreConstructionTimingTests {
    private func makeView() -> ShoppingAppView {
        ShoppingAppView(
            productSearch: LiveProductSearchService(),
            featureFlags: LiveFeatureFlagService(),
            now: { Date() }
        )
    }

    /// 构造视图（描述阶段之一）不得构建 Store。
    @Test func constructingViewDoesNotBuildStore() {
        let before = ShoppingStoreBootstrap.makeStoreCallCount

        _ = makeView()

        #expect(
            ShoppingStoreBootstrap.makeStoreCallCount == before,
            "ShoppingAppView.init 不得构建 Store —— 它会被父视图每次重绘重复调用"
        )
    }

    /// 求值 `body`（描述阶段之二）同样不得构建 Store。
    ///
    /// 注意它覆盖的是**另一种**写法：把 `makeStore` 直接写进 `body`
    /// （`ShoppingRootHost(store: ShoppingStoreBootstrap.makeStore(...))`）——
    /// 那种写法同样会随重绘线性构建。
    /// 它**不是**用来抓「改回 `init` 里构建」的（那条由上一个测试负责）。
    @Test func evaluatingBodyDoesNotBuildStore() {
        let view = makeView()
        let before = ShoppingStoreBootstrap.makeStoreCallCount

        _ = view.body

        #expect(
            ShoppingStoreBootstrap.makeStoreCallCount == before,
            "body 是描述阶段，不得有构建副作用；构建只应发生在首次 .onAppear"
        )
    }

    /// 对照组：`makeStore` 本身确实会推进计数器。
    ///
    /// 没有这条，上面两条断言可能只是因为探针坏了而"通过"（假阳性）。
    @Test func makeStoreAdvancesCounter() {
        let before = ShoppingStoreBootstrap.makeStoreCallCount

        _ = ShoppingStoreBootstrap.makeStore(
            productSearch: LiveProductSearchService(),
            featureFlags: LiveFeatureFlagService(),
            now: { Date() }
        )

        #expect(
            ShoppingStoreBootstrap.makeStoreCallCount == before + 1,
            "探针失效会让前两条断言变成假阳性"
        )
    }
}
