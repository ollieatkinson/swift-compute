// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Compute",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        .library(name: "Compute", targets: ["Compute"]),
    ],
    dependencies: [
        .package(url: "https://github.com/thousandyears/AnyCoding.git", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Compute",
            dependencies: [
                .product(name: "AnyCoding", package: "AnyCoding"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .testTarget(name: "ComputeTests", dependencies: ["Compute"]),
    ]
)
