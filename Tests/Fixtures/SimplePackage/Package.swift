// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimplePackage",
    products: [.library(name: "Auth", targets: ["Auth"])],
    targets: [
        .target(name: "Auth"),
        .testTarget(name: "AuthTests", dependencies: ["Auth"])
    ]
)
