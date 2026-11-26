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
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DraconisCoreTests", dependencies: ["DraconisCore"]),
    ]
)
