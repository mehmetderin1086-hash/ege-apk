// swift-tools-version: 6.2
// Kâğıt çekirdeği: arayüzden bağımsız PDF işlemleri. Mac'te `swift test` ile sınanır.
import PackageDescription

let package = Package(
    name: "KagitKit",
    defaultLocalization: "tr",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "KagitKit", targets: ["KagitKit"]),
    ],
    targets: [
        // PDFium (BSD-3/Apache-2.0): araclar/pdfium-hazirla.sh üretir, git dışıdır.
        .binaryTarget(name: "pdfium", path: "Ikili/pdfium.xcframework"),
        .target(
            name: "KagitKit",
            dependencies: ["pdfium"],
            path: "Sources/KagitKit",
            resources: [.copy("Kaynaklar/Yazitipleri")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "KagitKitTests",
            dependencies: ["KagitKit"],
            path: "Tests/KagitKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
