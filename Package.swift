// swift-tools-version:5.3.0
import PackageDescription

let package = Package(
    name: "pineapple",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "LambdaRuntimeAPI", targets: ["LambdaRuntimeAPI"])

    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.54.0"))
    ],
    targets: [
        .target(
            name: "LambdaRuntimeAPI",
            path: "./Source/LambdaRuntimeAPI"
        ),
        .target(
            name: "LambdaRuntimeAPIDemo",
            dependencies: [
                "LambdaRuntimeAPI"
            ],
            path: "./Source/LambdaRuntimeAPIDemo"
        ),
        .target(
            name: "Sandbox",
            dependencies: [
                .product(name: "Vapor", package: "vapor")
            ],
            path: "./Source/Sandbox"
        )
    ]
)
