// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DraconisCross",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "draconis-engine", targets: ["DraconisEngine"])],
    dependencies: [
        .package(path: "../Core"),
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
        // Headless: the Linux and Windows UI (Desktop/, Rust) runs it and talks
        // JSON lines over stdin/stdout.
        .executableTarget(
            name: "DraconisEngine",
            dependencies: [
                "DraconisPlatform",
                .product(name: "DraconisCore", package: "Core"),
            ],
            path: "Sources/DraconisEngine",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "DraconisPlatformTests", dependencies: ["DraconisPlatform"]),
    ]
)
