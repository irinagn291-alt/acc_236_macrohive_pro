// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HiveRIBs",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "HiveRIBs", targets: ["HiveRIBs"])
    ],
    targets: [
        .target(name: "HiveRIBs")
    ]
)
