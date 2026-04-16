// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WorkLogger",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", revision: "swift-6.2.4-RELEASE")
    ],
    targets: [
        .target(
            name: "WorkLoggerLib",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "WorkLogger",
            dependencies: ["WorkLoggerLib"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "WorkLoggerTests",
            dependencies: [
                "WorkLoggerLib",
                .product(name: "Testing", package: "swift-testing")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)