// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Compute",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v17),
    ],
    products: [
        .library(name: "Brain", targets: ["Brain"]),
        .library(name: "Compute", targets: ["Compute"]),
        .library(name: "_JSON", targets: ["_JSON"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.0"),
        .package(url: "https://github.com/thousandyears/AnyCoding.git", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Brain",
            dependencies: [
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .target(
            name: "Compute",
            dependencies: [
                "Brain",
                "_JSON",
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "AnyCoding", package: "AnyCoding"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .target(
            name: "_JSON",
            dependencies: [
                .product(name: "AnyCoding", package: "AnyCoding"),
            ]
        ),
        .testTarget(
            name: "BrainTests",
            dependencies: [
                "Brain",
                .product(name: "Algorithms", package: "swift-algorithms"),
            ]
        ),
        .testTarget(name: "ComputeTests", dependencies: ["Compute"]),
        .testTarget(name: "_JSONTests", dependencies: ["_JSON"]),
    ]
)
