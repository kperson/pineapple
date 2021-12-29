// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "pineapple",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "LambdaRuntimeAPI", targets: ["LambdaRuntimeAPI"]),
        .library(name: "LambdaApp", targets: ["LambdaApp"]),
        .library(name: "LambdaVapor", targets: ["LambdaVapor"]),
        .library(name: "LambdaApiGateway", targets: ["LambdaApiGateway"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.54.0")),
        .package(url: "https://github.com/soto-project/soto.git", .upToNextMajor(from: "5.11.0"))
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
            name: "LambdaProxyRuntimeAPI",
            dependencies: [
                "LambdaVapor",
                "LambdaApiGateway",
                .product(name: "SotoDynamoDB", package: "soto")
            ],
            path: "./Source/LambdaProxyRuntimeAPI"
        ),
        .target(
            name: "LambdaVaporDemo",
            dependencies: [
                "LambdaVapor",
                "LambdaApiGateway"
            ],
            path: "./Source/LambdaVaporDemo"
        )
    ],
    swiftLanguageVersions: [.v5]
)
