// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LarkdownCore",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LarkdownCore", targets: ["LarkdownCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "LarkdownCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LarkdownCoreTests",
            dependencies: ["LarkdownCore"],
            resources: [
                .process("Fixtures")
            ]
        )
    ]
)
