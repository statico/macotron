// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Macotron",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Self-updates. Ships as a prebuilt XCFramework, so `make bundle` copies
        // and signs Sparkle.framework into the app.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
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
            path: "Sources/MacotronEngine",
            resources: [
                .copy("Resources/agents-template.md"),
            ]
        ),

        // UI (LauncherPanel + MenuBar + SwiftUI views)
        .target(
            name: "MacotronUI",
            dependencies: [
                "MacotronEngine",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
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

        .executableTarget(
            name: "PluginScan",
            dependencies: ["AI", "MacotronEngine"],
            path: "Sources/PluginScanCLI",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-weak_framework",
                    "-Xlinker", "FoundationModels",
                ]),
            ]
        ),

        // Main app executable
        .executableTarget(
            name: "Macotron",
            dependencies: ["MacotronEngine", "MacotronUI", "Modules", "AI"],
            path: "Sources/Macotron",
            resources: [
                .copy("Resources/macotron-runtime.js"),
                .copy("Resources/macotron.d.ts"),
            ],
            linkerSettings: [
                // `make bundle` copies Sparkle.framework into the app, so the
                // executable has to look there for it at launch.
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),

        // Tests
        .testTarget(
            name: "MacotronTests",
            dependencies: ["MacotronEngine", "MacotronUI", "AI", "Modules", "SMCKit"],
            exclude: ["Fixtures"]
        ),
    ]
)
