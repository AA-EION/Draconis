// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DraconisCross",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/moreSwift/swift-cross-ui.git", .upToNextMinor(from: "0.11.0")),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
    ],
    targets: [
        .target(
            name: "DraconisPlatform",
            dependencies: [
                .product(name: "DraconisCore", package: "Core"),
                // Only Linux downloads runners; BoringSSL's C++ doesn't build with Swift's Clang against current MSVC headers.
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Draconis",
            dependencies: [
                "DraconisPlatform",
                .product(name: "DraconisCore", package: "Core"),
                .product(name: "SwiftCrossUI", package: "swift-cross-ui"),
                .product(name: "DefaultBackend", package: "swift-cross-ui"),
                .product(name: "GtkBackend", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
                .product(name: "Gtk", package: "swift-cross-ui", condition: .when(platforms: [.linux])),
                .product(name: "WinUIBackend", package: "swift-cross-ui", condition: .when(platforms: [.windows])),
            ],
            path: "Sources/DraconisCross",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DraconisPlatformTests", dependencies: ["DraconisPlatform"]),
    ]
)
