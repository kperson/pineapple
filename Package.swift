// swift-tools-version:6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "pineapple",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "LambdaApp", targets: ["LambdaApp"]),
        .library(name: "JSONSchemaDSL", targets: ["JSONSchemaDSL"]),
        .library(name: "JSONValueCoding", targets: ["JSONValueCoding"]),
        .library(name: "MCP", targets: ["MCP"]),
        .library(name: "MCPLambda", targets: ["MCPLambda"]),
        .library(name: "MCPHummingbird", targets: ["MCPHummingbird"]),
        .library(name: "MCPStdio", targets: ["MCPStdio"]),
        .library(name: "SimpleMathServer", targets: ["SimpleMathServer"]),
        .executable(name: "MCPExample", targets: ["MCPExample"])
    ],
    dependencies: [
        .package(url: "https://github.com/soto-project/soto.git", .upToNextMinor(from: "7.9.0")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMinor(from: "1.6.0")),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", .upToNextMinor(from: "1.2.0")),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", .upToNextMinor(from: "2.16.0")),
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0")
    ],
    
    targets: [
        .target(
            name: "LambdaApp",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
            ],
            path: "./Source/LambdaApp",
            exclude: ["README.md"]
        ),
        .target(
            name: "JSONSchemaDSL",
            dependencies: [],
            path: "./Source/JSONSchemaDSL"
        ),
        .target(
            name: "JSONValueCoding",
            dependencies: [
                "MCPMacros"
            ],
            path: "./Source/JSONValueCoding"
        ),
        .target(
            name: "MCP",
            dependencies: [
                "JSONValueCoding",
                "MCPMacros",
                .product(name: "Logging", package: "swift-log")
            ],
            path: "./Source/MCP",
            exclude: ["README.md"]
        ),
        .macro(
            name: "MCPMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "./Source/MCPMacros"
        ),
        .target(
            name: "MCPLambda",
            dependencies: [
                "MCP",
                "LambdaApp"
            ],
            path: "./Source/MCPLambda",
            exclude: ["README.md"]
        ),
        .target(
            name: "MCPHummingbird",
            dependencies: [
                "MCP",
                .product(name: "Hummingbird", package: "hummingbird")
            ],
            path: "./Source/MCPHummingbird",
            exclude: ["README.md"]
        ),
        .target(
            name: "MCPStdio",
            dependencies: [
                "MCP"
            ],
            path: "./Source/MCPStdio",
            exclude: ["README.md"]
        ),
        .target(
            name: "SimpleMathServer",
            dependencies: [
                "MCP"
            ],
            path: "./Source/SimpleMathServer"
        ),
        .executableTarget(
            name: "MCPExample",
            dependencies: [
                "MCP",
                "MCPLambda",
                "MCPHummingbird",
                "MCPStdio",
                "SimpleMathServer"
            ],
            path: "./Source/MCPExample",
            exclude: ["README.md"]
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
            name: "TestSupport",
            dependencies: [
                "MCP",
                "SimpleMathServer"
            ],
            path: "./Tests/TestSupport"
        ),
        .testTarget(
            name: "MCPTests",
            dependencies: [
                "MCP"
            ],
            path: "./Tests/MCPTests"
        ),
        .testTarget(
            name: "JSONValueCodingTests",
            dependencies: [
                "JSONValueCoding"
            ],
            path: "./Tests/JSONValueCodingTests"
        ),
        .testTarget(
            name: "MCPHummingbirdTests",
            dependencies: [
                "MCPHummingbird",
                "TestSupport",
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ],
            path: "./Tests/MCPHummingbirdTests"
        ),
        .testTarget(
            name: "MCPLambdaTests",
            dependencies: [
                "MCPLambda",
                "TestSupport",
                "LambdaApp"
            ],
            path: "./Tests/MCPLambdaTests"
        ),
        .testTarget(
            name: "MCPStdioTests",
            dependencies: [
                "MCPStdio",
                "TestSupport"
            ]
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
