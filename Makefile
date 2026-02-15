APP_NAME = Macotron
BUILD_DIR = /tmp/macotron-build
BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY = $(BUILD_DIR)/debug/$(APP_NAME)
BUNDLE_ID = com.macotron.app

.PHONY: build run bundle clean dev reload eval screenshot

# Compile
build:
	swift build --build-path $(BUILD_DIR)

# Compile + bundle + run
run: bundle
	open $(BUNDLE)

# Compile + bundle + run with debug server on :7777
dev: bundle
	$(BUNDLE)/Contents/MacOS/$(APP_NAME) --debug-server

# Create .app bundle from compiled binary
bundle: build
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(BUNDLE)/Contents/
	@cp Sources/Macotron/Resources/macotron-runtime.js $(BUNDLE)/Contents/Resources/
	@cp Sources/Macotron/Resources/macotron.d.ts $(BUNDLE)/Contents/Resources/
	@codesign --force --sign - --entitlements Resources/Macotron.entitlements $(BUNDLE)
	@echo "Built $(BUNDLE)"

# Debug server interactions
reload:
	@curl -s -X POST http://localhost:7777/reload

eval:
	@curl -s -X POST http://localhost:7777/eval \
		-H "Content-Type: application/json" \
		-d '{"js": "$(JS)"}'

health:
	@curl -s http://localhost:7777/health | python3 -m json.tool

snippets:
	@curl -s http://localhost:7777/snippets | python3 -m json.tool

commands:
	@curl -s http://localhost:7777/commands | python3 -m json.tool

clean:
	swift package clean --build-path $(BUILD_DIR)
	rm -rf $(BUNDLE)

# Release build
release:
	swift build -c release --build-path $(BUILD_DIR)
	@echo "TODO: bundle, sign with Developer ID, notarize, create DMG"
