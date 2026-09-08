// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AintoApp",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20")
    ],
    targets: [
        // C bridge to Rust static library
        .systemLibrary(
            name: "AintoCore",
            path: "AintoCoreBridge"
        ),
        // Main application
        .executableTarget(
            name: "AintoApp",
            dependencies: [
                "AintoCore",
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources",
            resources: [
                .copy("../Resources"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(Context.packageDirectory)/../ainto-core/target/release",
                    "-lainto_core",
                ]),
                // System frameworks needed by Rust code
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "AintoAppTests",
            dependencies: [
                "AintoApp",
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Tests"
        )
    ]
)
