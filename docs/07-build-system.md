# Build System & Development

No Xcode GUI. Everything from the CLI.

## Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Macotron",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CQuickJS",
            path: "Vendor/quickjs-ng",
            sources: ["quickjs.c", "libunicode.c", "libregexp.c", "cutils.c", "quickjs-libc.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("CONFIG_VERSION", to: "\"0.11.0\""),
                .define("CONFIG_BIGNUM"),
                .unsafeFlags(["-w"])
            ]
        ),
        .executableTarget(
            name: "Macotron",
            dependencies: ["MacotronEngine", "MacotronUI"],
            path: "Sources/Macotron",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        ),
        .target(name: "MacotronEngine", dependencies: ["CQuickJS"], path: "Sources/MacotronEngine"),
        .target(name: "MacotronUI", dependencies: ["MacotronEngine"], path: "Sources/MacotronUI"),
        .target(name: "Modules", dependencies: ["MacotronEngine"], path: "Sources/Modules"),
        .target(name: "AI", dependencies: ["MacotronEngine"], path: "Sources/AI"),
        .testTarget(name: "MacotronTests", dependencies: ["MacotronEngine"]),
    ]
)
```

## Makefile

```makefile
APP_NAME = Macotron
BUNDLE = .build/$(APP_NAME).app
BINARY = .build/debug/$(APP_NAME)

.PHONY: build run bundle clean dev

build:
	swift build

run: bundle
	open $(BUNDLE)

dev: bundle
	$(BUNDLE)/Contents/MacOS/$(APP_NAME) --debug-server

bundle: build
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(BUNDLE)/Contents/
	@cp Resources/macotron-runtime.js $(BUNDLE)/Contents/Resources/
	@cp Resources/macotron.d.ts $(BUNDLE)/Contents/Resources/
	@codesign --force --sign - --entitlements Resources/Macotron.entitlements $(BUNDLE)

clean:
	swift package clean
	rm -rf $(BUNDLE)
```

## Debug HTTP Server

Embedded HTTP server (debug builds only) on port 7777:

| Endpoint | Method | Description |
|---|---|---|
| `/screenshot` | GET | PNG of launcher panel |
| `/snapshot` | GET | Accessibility tree as JSON |
| `/eval` | POST | Evaluate JS in engine |
| `/menubar` | GET | Current menubar items |
| `/reload` | POST | Trigger snippet reload |
| `/snippets` | GET | List loaded snippets |
| `/open` | POST | Toggle launcher panel |
