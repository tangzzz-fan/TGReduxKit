// swift-tools-version: 6.0
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
        .library(name: "TGReduxKitCore", targets: ["TGReduxKitCore"]),
        .library(name: "TGReduxKitRuntime", targets: ["TGReduxKitRuntime"]),
        .library(name: "TGReduxKitUI", targets: ["TGReduxKitUI"]),
        .library(name: "TGReduxKitDebug", targets: ["TGReduxKitDebug"]),
        .library(name: "TGReduxKitTesting", targets: ["TGReduxKitTesting"]),
        .library(name: "TGReduxKit", targets: ["TGReduxKit"]),
    ],
    targets: [
        .target(name: "TGReduxKitCore"),
        .target(
            name: "TGReduxKitRuntime",
            dependencies: ["TGReduxKitCore"]
        ),
        .target(
            name: "TGReduxKitUI",
            dependencies: ["TGReduxKitCore", "TGReduxKitRuntime"]
        ),
        .target(
            name: "TGReduxKitDebug",
            dependencies: ["TGReduxKitCore", "TGReduxKitRuntime"]
        ),
        .target(
            name: "TGReduxKitTesting",
            dependencies: ["TGReduxKitCore"]
        ),
        .target(
            name: "TGReduxKit",
            dependencies: [
                "TGReduxKitCore",
                "TGReduxKitRuntime",
                "TGReduxKitUI",
                "TGReduxKitDebug"
            ]
        ),
        .testTarget(
            name: "TGReduxKitTests",
            dependencies: [
                "TGReduxKitCore",
                "TGReduxKitRuntime",
                "TGReduxKitUI",
                "TGReduxKitDebug",
                "TGReduxKitTesting",
                "TGReduxKit"
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
