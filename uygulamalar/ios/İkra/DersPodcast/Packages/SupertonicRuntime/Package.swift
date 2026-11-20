// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SupertonicRuntime", platforms: [.iOS(.v18)],
    products: [.library(name: "SupertonicRuntime", targets: ["SupertonicRuntime"])],
    targets: [.target(name: "SupertonicRuntime")])
