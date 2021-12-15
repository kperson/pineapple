// swift-tools-version:5.3.0
import PackageDescription

let package = Package(
    name: "pineapple",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "LambdaRuntimeAPI", targets: ["LambdaRuntimeAPI"]),
        .library(name: "LambdaApp", targets: ["LambdaApp"]),
        .library(name: "LambdaVapor", targets: ["LambdaVapor"])
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
            name: "LambdaApp",
            dependencies: [
                "LambdaRuntimeAPI"
            ],
            path: "./Source/LambdaApp"
        ),
        .target(
            name: "LambdaVapor",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "LambdaApp"
            ],
            path: "./Source/LambdaVapor"
        ),
        .target(
            name: "LambdaVaporDemo",
            dependencies: [
                "LambdaVapor"
            ],
            path: "./Source/LambdaVaporDemo"
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
