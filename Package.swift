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
        .package(url: "https://github.com/soto-project/soto.git", .upToNextMajor(from: "5.11.0")),
        .package(url: "https://github.com/kperson/swift-async-http.git", .upToNextMajor(from: "1.1.1"))
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
            name: "LambdaRemoteClient",
            dependencies: [
                "LambdaRuntimeAPI"
            ],
            path: "./Source/LambdaRemoteClient"
        ),
        .target(
            name: "LambdaRemoteAPI",
            dependencies: [
                "LambdaVapor",
                "LambdaApiGateway",
                "LambdaRemoteClient",
                .product(name: "AsyncHttp", package: "swift-async-http"),
                .product(name: "SotoDynamoDB", package: "soto")
            ],
            path: "./Source/LambdaRemoteAPI"
        ),
        .executableTarget(
            name: "LambdaRemoteAPIApp",
            dependencies: [
                "LambdaRemoteAPI"
            ],
            path: "./Source/LambdaRemoteAPIApp"
        ),
        .testTarget(
            name: "LambdaRemoteAPITests",
            dependencies: [
                "LambdaRemoteAPI"
            ],
            path: "./Tests/LambdaRemoteAPITests"
        ),
        .executableTarget(
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
