// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShoppingDomain",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "ShoppingDomain", targets: ["ShoppingDomain"])
    ],
    dependencies: [
        .package(path: "../../../../TGNavigationStack")
    ],
    targets: [
        .target(
            name: "ShoppingDomain",
            dependencies: ["TGNavigationStack"]
        )
    ],
    swiftLanguageModes: [.v6]
)
