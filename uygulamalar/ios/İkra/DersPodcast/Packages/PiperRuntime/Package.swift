// swift-tools-version: 5.9
import PackageDescription

// Only the iOS binaries are included. URLs and hashes come from the upstream
// sherpa-onnx 1.13.8 and onnxruntime-libs 1.28.2 package manifests.
let package = Package(
    name: "PiperRuntime",
    platforms: [.iOS("18.0")],
    products: [.library(name: "PiperRuntime", targets: ["PiperRuntime"])],
    targets: [
        .binaryTarget(name: "SherpaOnnxIOS",
            url: "https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-ios-static.xcframework.zip",
            checksum: "6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de"),
        .binaryTarget(name: "OnnxruntimeIOS",
            url: "https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.28.2/onnxruntime-ios-static-xcframework-1.28.2.xcframework.zip",
            checksum: "2c2299acbb461d26d4bac4bc85985d40e7c7177ed6072703ae0846d88b0b4599"),
        .target(name: "PiperRuntime", dependencies: ["SherpaOnnxIOS", "OnnxruntimeIOS"],
            linkerSettings: [.linkedLibrary("c++"), .linkedFramework("CoreML"), .linkedFramework("Accelerate")])
    ]
)
