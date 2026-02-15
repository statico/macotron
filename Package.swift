// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Macotron",
    platforms: [.macOS(.v15)],
    targets: [
        // QuickJS C library (quickjs-ng amalgam build)
        .target(
            name: "CQuickJS",
            path: "Vendor/quickjs-ng",
            sources: ["quickjs-amalgam.c", "quickjs-swift-helpers.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("CONFIG_VERSION", to: "\"0.12.1\""),
                .define("CONFIG_BIGNUM"),
                .unsafeFlags(["-w"]) // suppress warnings from third-party C code
            ]
        ),

        // Core engine (QuickJS + EventBus + SnippetManager)
        .target(
            name: "MacotronEngine",
            dependencies: ["CQuickJS"],
            path: "Sources/MacotronEngine"
        ),

        // UI (LauncherPanel + MenuBar + SwiftUI views)
        .target(
            name: "MacotronUI",
            dependencies: ["MacotronEngine"],
            path: "Sources/MacotronUI"
        ),

        // Native modules (window, keyboard, screen, etc.)
        .target(
            name: "Modules",
            dependencies: ["MacotronEngine", "AI"],
            path: "Sources/Modules"
        ),

        // AI providers
        .target(
            name: "AI",
            dependencies: ["MacotronEngine"],
            path: "Sources/AI"
        ),

        // Main app executable
        .executableTarget(
            name: "Macotron",
            dependencies: ["MacotronEngine", "MacotronUI", "Modules", "AI"],
            path: "Sources/Macotron",
            resources: [
                .copy("Resources/macotron-runtime.js"),
                .copy("Resources/macotron.d.ts"),
            ]
        ),

        // Tests
        .testTarget(
            name: "MacotronTests",
            dependencies: ["MacotronEngine"]
        ),
    ]
)
