// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shopping",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "Shopping", targets: ["Shopping"])
    ],
    dependencies: [
        .package(path: "../../../../TGNavigationStack"),
        .package(path: "../../..")
    ],
    targets: [
        .target(
            name: "Shopping",
            dependencies: [
                "TGNavigationStack",
                .product(name: "TGReduxKit", package: "TGReduxKit")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
