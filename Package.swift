// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TGReduxKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "TGReduxKit",
            targets: ["TGReduxKit"]
        ),
    ],
    targets: [
        .target(
            name: "TGReduxKit"
        ),
        .testTarget(
            name: "TGReduxKitTests",
            dependencies: ["TGReduxKit"]
        ),
    ]
)
