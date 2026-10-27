// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "PairwiseCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PairwiseCore", targets: ["PairwiseCore"])],
    targets: [
        .target(name: "PairwiseCore"),
        .testTarget(name: "PairwiseCoreTests", dependencies: ["PairwiseCore"])
    ]
)
