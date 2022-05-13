// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "pineapple",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "LambdaRuntimeAPI", targets: ["LambdaRuntimeAPI"]),
        .library(name: "LambdaApp", targets: ["LambdaApp"])
    ],
    dependencies: [
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
            name: "SystemTestsCommon",
            dependencies: [
                .product(name: "SotoDynamoDB", package: "soto")
            ],
            path: "./Source/SystemTestsCommon"
        ),
        .executableTarget(
            name: "SystemTestsApp",
            dependencies: [
                "LambdaApp",
                "SystemTestsCommon",
                .product(name: "SotoDynamoDB", package: "soto")
            ],
            path: "./Source/SystemTestsApp"
        ),
        .testTarget(
            name: "SystemTests",
            dependencies: [
                "SystemTestsCommon",
                .product(name: "SotoDynamoDB", package: "soto"),
                .product(name: "SotoSQS", package: "soto"),
                .product(name: "SotoSNS", package: "soto"),
                .product(name: "SotoS3", package: "soto")
            ],
            path: "./Tests/SystemTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
