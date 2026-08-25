import Foundation
import TGNavigationStack

// MARK: - Models

public struct Product: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let price: Decimal
    public let description: String
    public let imageName: String

    public init(id: UUID = UUID(), name: String, price: Decimal, description: String, imageName: String) {
        self.id = id
        self.name = name
        self.price = price
        self.description = description
        self.imageName = imageName
    }
}

public struct CartItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let product: Product
    public var quantity: Int

    public init(product: Product, quantity: Int = 1) {
        self.id = UUID()
        self.product = product
        self.quantity = quantity
    }
}

// MARK: - Route

public enum ShoppingRoute: TGRoute {
    case list
    case detail(UUID)
    case cart
}
