// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Compute",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "Compute", targets: ["Compute"]),
    ],
    dependencies: [
        .package(url: "https://github.com/thousandyears/AnyCoding.git", from: "0.1.0"),
        .package(url: "https://github.com/pointfreeco/swift-custom-dump.git", from: "1.5.0"),
        .package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.31.0", traits: []),
    ],
    targets: [
        .target(
            name: "Compute",
            dependencies: [
                .product(name: "AnyCoding", package: "AnyCoding"),
                .product(name: "CustomDump", package: "swift-custom-dump"),
            ]
        ),
        .executableTarget(
            name: "ComputeBenchmarks",
            dependencies: [
                "Compute",
                .product(name: "Benchmark", package: "package-benchmark"),
            ],
            path: "Benchmarks/ComputeBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
            ]
        ),
        .executableTarget(
            name: "ComputeProfile",
            dependencies: ["Compute"],
            path: "Benchmarks/ComputeProfile"
        ),
        .testTarget(name: "ComputeTests", dependencies: ["Compute"]),
    ]
)
