// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProxyKit",
    platforms: [.iOS("18.0"), .macOS("15.0")],
    products: [.library(name: "ProxyKit", targets: ["ProxyKit"])],
    targets: [
        .target(name: "ProxyKit"),
        .testTarget(name: "ProxyKitTests", dependencies: ["ProxyKit"]),
    ]
)
