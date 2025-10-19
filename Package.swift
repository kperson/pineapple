// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "pineapple",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "LambdaApp", targets: ["LambdaApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto.git", .upToNextMinor(from: "7.9.0")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMinor(from: "1.6.0")),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", .upToNextMinor(from: "1.2.0"))
    ],
    
    targets: [
        .target(
            name: "LambdaApp",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events")
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
            name: "LambdaHandler",
            dependencies: [
                "SystemTestsCommon",
                "LambdaApp",
                .product(name: "SotoDynamoDB", package: "soto"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "./Source/LambdaHandler"
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
            name: "LambdaAppTests",
            dependencies: [
                "LambdaApp"
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
