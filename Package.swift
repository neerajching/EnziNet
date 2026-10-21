// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EnziNet",
    platforms: [.iOS(.v15), .macOS(.v12), .tvOS(.v15), .watchOS(.v8)],
    products: [
        .library(name: "EnziNet", targets: ["EnziNet"])
    ],
    targets: [
        .target(name: "EnziNet"),
        .testTarget(name: "EnziNetTests", dependencies: ["EnziNet"])
    ]
)
