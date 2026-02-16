APP_NAME = Macotron
BUILD_DIR = /tmp/macotron-build
BUNDLE = $(HOME)/Applications/$(APP_NAME).app
BINARY = $(BUILD_DIR)/debug/$(APP_NAME)
BUNDLE_ID = com.macotron.app

# Set SIGN_IDENTITY to a certificate name for stable signing (permissions persist across builds).
# Create one in Keychain Access → Certificate Assistant → Create a Certificate → Code Signing.
# Leave empty to use ad-hoc signing (permissions reset every build).
SIGN_IDENTITY ?=

.PHONY: build run bundle clean cleanprefs dev reload eval screenshot

# Compile
build:
	swift build --build-path $(BUILD_DIR)

# Compile + bundle + run (kills existing instance first)
run: bundle
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	open $(BUNDLE)

# Compile + bundle + run with debug server on :7777
dev: bundle
	$(BUNDLE)/Contents/MacOS/$(APP_NAME) --debug-server

# Create .app bundle from compiled binary
bundle: build
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@mkdir -p "$(BUNDLE)/Contents/Resources"
	@cp $(BINARY) "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/"
	@cp Sources/Macotron/Resources/macotron-runtime.js "$(BUNDLE)/Contents/Resources/"
	@cp Sources/Macotron/Resources/macotron.d.ts "$(BUNDLE)/Contents/Resources/"
	@cp Resources/AppIcon.icns "$(BUNDLE)/Contents/Resources/"
	@cp Resources/banner.png "$(BUNDLE)/Contents/Resources/"
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		codesign --force --sign "$(SIGN_IDENTITY)" --entitlements Resources/Macotron.entitlements "$(BUNDLE)"; \
	else \
		codesign --force --sign - --entitlements Resources/Macotron.entitlements "$(BUNDLE)"; \
	fi
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
	rm -rf "$(BUNDLE)"

# Remove all user preferences and data for a fresh launch
cleanprefs:
	@pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf ~/Library/Application\ Support/$(APP_NAME)
	defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@echo "Cleaned preferences and data for $(APP_NAME)"

# Release build
release:
	swift build -c release --build-path $(BUILD_DIR)
	@echo "TODO: bundle, sign with Developer ID, notarize, create DMG"
