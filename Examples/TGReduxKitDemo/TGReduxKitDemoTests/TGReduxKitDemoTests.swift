//
//  TGReduxKitDemoTests.swift
//  TGReduxKitDemoTests
//
//  Created by 小苹果 on 2026/1/14.
//

import Foundation
import Testing
@testable import TGReduxKitDemo
import Shopping

struct TGReduxKitDemoTests {
    @Test func visibleProductsAppliesPremiumCatalogFlag() async throws {
        let products = [
            Product(name: "MacBook Pro", price: 1999, description: "Laptop", imageName: "laptopcomputer"),
            Product(name: "AirPods Pro", price: 249, description: "Audio", imageName: "airpods")
        ]

        let result = visibleProducts(
            from: products,
            matching: "",
            flags: FeatureFlagSnapshot(
                isExpressCheckoutEnabled: false,
                showsFreeShippingBanner: false,
                showsRecommendedBadge: false,
                hidesBudgetProducts: true
            )
        )

        #expect(result.map(\.name) == ["MacBook Pro"])
    }

    @Test func visibleProductsKeepsSearchAndFlagsInSync() async throws {
        let products = [
            Product(name: "MacBook Pro", price: 1999, description: "Laptop", imageName: "laptopcomputer"),
            Product(name: "Apple Watch", price: 399, description: "Watch", imageName: "applewatch")
        ]

        let result = visibleProducts(
            from: products,
            matching: "Apple",
            flags: FeatureFlagSnapshot(
                isExpressCheckoutEnabled: true,
                showsFreeShippingBanner: true,
                showsRecommendedBadge: true,
                hidesBudgetProducts: true
            )
        )

        #expect(result.isEmpty)
    }
}
