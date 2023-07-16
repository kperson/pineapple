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
        .library(name: "Messaging", targets: ["Messaging"]),
        .library(name: "LambdaPlus", targets: ["LambdaPlus"])
    ],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto.git", .upToNextMajor(from: "5.13.0")),
        .package(url: "https://github.com/cx-org/CombineX", from: "0.4.0")
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
            name: "Messaging",
            dependencies: [
            ],
            path: "./Source/Messaging"
        ),
        .target(
            name: "LambdaPlus",
            dependencies: [
                "Messaging",
                "LambdaApp",
                .product(name: "SotoSQS", package: "soto"),
                .product(name: "SotoSNS", package: "soto")
            ],
            path: "./Source/LambdaPlus"
        ),
        .target(
            name: "LambdaCombine",
            dependencies: [
                "LambdaApp",
                .product(name: "CombineX", package: "CombineX")
            ],
            path: "./Source/LambdaCombine"
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
                "LambdaApp",
                .product(name: "SotoDynamoDB", package: "soto"),
                .product(name: "SotoSQS", package: "soto"),
                .product(name: "SotoSNS", package: "soto"),
                .product(name: "SotoS3", package: "soto")
            ],
            path: "./Tests/SystemTests"
        ),
        .testTarget(
            name: "LambdaPlusTests",
            dependencies: [
                "LambdaPlus"
            ],
            path: "./Tests/LambdaPlusTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
