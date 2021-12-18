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
        .library(name: "LambdaVapor", targets: ["LambdaVapor"]),
        .library(name: "LambdaApiGateway", targets: ["LambdaApiGateway"])
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
            name: "LambdaApiGateway",
            dependencies: [
                "LambdaApp"
            ],
            path: "./Source/LambdaApiGateway"
        ),
        .target(
            name: "LambdaVapor",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "LambdaApiGateway"
            ],
            path: "./Source/LambdaVapor"
        ),
        .target(
            name: "LambdaVaporDemo",
            dependencies: [
                "LambdaVapor",
                "LambdaApiGateway"
            ],
            path: "./Source/LambdaVaporDemo"
        )
    ]
)
