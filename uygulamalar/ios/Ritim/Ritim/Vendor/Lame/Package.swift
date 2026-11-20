// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Lame",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "CLame", targets: ["CLame"])],
    targets: [
        .target(
            name: "CLame",
            exclude: ["libmp3lame/mpglib_interface.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("HAVE_CONFIG_H", to: "1"),
                // The codec is also used by development builds installed on a
                // phone. Unoptimized inner loops waste CPU during long tracks.
                .unsafeFlags(["-O2"], .when(configuration: .debug)),
                .headerSearchPath("."),
                .headerSearchPath("libmp3lame")
            ]
        )
    ],
    cLanguageStandard: .c99
)
