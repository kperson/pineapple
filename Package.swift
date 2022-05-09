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
    dependencies: [],
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
        .testTarget(
            name: "SystemTests",
            dependencies: [
                "LambdaApp",
            ],
            path: "./Tests/SystemTests"
        ),
        .executableTarget(
            name: "SystemTestsApp",
            dependencies: [
                "LambdaApp"
            ],
            path: "./Source/SystemTestsApp"
        )
    ],
    swiftLanguageVersions: [.v5]
)
