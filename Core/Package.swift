// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DraconisCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DraconisCore", targets: ["DraconisCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "DraconisCore",
            // Windows has no zlib headers; it unpacks with its bundled tar.exe.
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation",
                                    condition: .when(platforms: [.macOS, .linux]))],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DraconisCoreTests", dependencies: [
            "DraconisCore",
            .product(name: "ZIPFoundation", package: "ZIPFoundation", condition: .when(platforms: [.macOS, .linux])),
        ]),
    ]
)
