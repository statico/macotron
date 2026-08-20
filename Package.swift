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
                .define("CONFIG_VERSION", to: "\"0.16.1\""),
                .unsafeFlags(["-w"]) // suppress warnings from third-party C code
            ]
        ),

        .target(
            name: "SMCKit",
            path: "Sources/SMCKit"
        ),

        // Core engine (QuickJS + EventBus + ModuleManager)
        .target(
            name: "MacotronEngine",
            dependencies: ["CQuickJS", "SMCKit"],
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
            dependencies: ["MacotronEngine", "AI", "SMCKit"],
            path: "Sources/Modules"
        ),

        // AI providers
        .target(
            name: "AI",
            dependencies: ["MacotronEngine"],
            path: "Sources/AI",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-weak_framework",
                    "-Xlinker", "FoundationModels",
                ]),
            ]
        ),

        .executableTarget(
            name: "MacotronHelper",
            dependencies: ["SMCKit"],
            path: "Sources/MacotronHelper"
        ),

        // Main app executable
        .executableTarget(
            name: "Macotron",
            dependencies: ["MacotronEngine", "MacotronUI", "Modules"],
            path: "Sources/Macotron",
            resources: [
                .copy("Resources/macotron-runtime.js"),
                .copy("Resources/macotron.d.ts"),
            ]
        ),

        // Tests
        .testTarget(
            name: "MacotronTests",
            dependencies: ["MacotronEngine", "MacotronUI", "AI", "Modules", "SMCKit"]
        ),
    ]
)
