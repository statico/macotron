APP_NAME = Macotron
BUILD_DIR = /tmp/macotron-build
BUNDLE = $(HOME)/Applications/$(APP_NAME).app
BINARY = $(BUILD_DIR)/debug/$(APP_NAME)
BUNDLE_ID = io.statico.macotron

# Root helper for fan-speed writes. SMAppService loads it from inside the bundle,
# so the plist must use BundleProgram and the helper must be signed before the
# outer bundle is sealed.
HELPER_NAME = MacotronFanHelper
HELPER_LABEL = $(BUNDLE_ID).fanhelper
HELPER_BINARY = $(BUILD_DIR)/debug/$(HELPER_NAME)

# Stable signing keeps a fixed CDHash, so macOS permissions persist across builds.
# Prefer a Developer ID, which is the only identity that satisfies SMAppService:
# it refuses to register a daemon unless the app and helper share a real Team ID.
# Otherwise fall back to a self-signed Code Signing certificate named Macotron-Dev
# (Keychain Access → Certificate Assistant → Create a Certificate), which keeps
# permissions but cannot install the fan helper. Last resort is ad-hoc signing,
# which resets permissions on every build.
#
# A self-signed certificate is untrusted, so it is missing from `find-identity -v`
# even though codesign accepts it. Match on the name instead, and skip anything
# expired because codesign does reject those.
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning 2>/dev/null | \
	grep -v CSSMERR_TP_CERT_EXPIRED | \
	grep -m1 -o '"Developer ID Application[^"]*"' | tr -d '"')
ifeq ($(strip $(SIGN_IDENTITY)),)
SIGN_IDENTITY := $(shell security find-identity -p codesigning 2>/dev/null | \
	grep -v CSSMERR_TP_CERT_EXPIRED | grep -m1 -o '"Macotron-Dev[^"]*"' | tr -d '"')
endif

# Hardened runtime is required alongside a Developer ID, and notarization later.
SIGN_FLAGS = $(if $(findstring Developer ID,$(SIGN_IDENTITY)),--options runtime,)

.DEFAULT_GOAL := help

.PHONY: help build run bundle check clean cleanprefs release

##@ General

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\033[0m\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Build

build: ## Compile the debug binary
	swift build --build-path $(BUILD_DIR)

bundle: build ## Create ~/Applications/Macotron.app
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@mkdir -p "$(BUNDLE)/Contents/Resources"
	@mkdir -p "$(BUNDLE)/Contents/Library/LaunchDaemons"
	@cp $(BINARY) "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp $(HELPER_BINARY) "$(BUNDLE)/Contents/MacOS/$(HELPER_NAME)"
	@cp Resources/$(HELPER_LABEL).plist "$(BUNDLE)/Contents/Library/LaunchDaemons/"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/"
	@cp Sources/Macotron/Resources/macotron-runtime.js "$(BUNDLE)/Contents/Resources/"
	@cp Sources/Macotron/Resources/macotron.d.ts "$(BUNDLE)/Contents/Resources/"
	@xcrun actool $(CURDIR)/Resources/$(APP_NAME).icon --compile "$(BUNDLE)/Contents/Resources" \
		--app-icon $(APP_NAME) --output-partial-info-plist $(BUILD_DIR)/icon-partial.plist \
		--platform macosx --minimum-deployment-target 15.0 --errors --warnings >/dev/null
	@cp Resources/banner.png "$(BUNDLE)/Contents/Resources/"
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) \
			"$(BUNDLE)/Contents/MacOS/$(HELPER_NAME)"; \
		codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) \
			--entitlements Resources/Macotron.entitlements "$(BUNDLE)"; \
		echo "Signed with $(SIGN_IDENTITY)"; \
	else \
		codesign --force --sign - "$(BUNDLE)/Contents/MacOS/$(HELPER_NAME)"; \
		codesign --force --sign - --entitlements Resources/Macotron.entitlements "$(BUNDLE)"; \
		printf '\033[33mWarning: ad-hoc signed. macOS permissions reset on every build.\033[0m\n'; \
		printf '\033[33mCreate a Code Signing certificate in Keychain Access to keep them.\033[0m\n'; \
	fi
	@if codesign -dv "$(BUNDLE)" 2>&1 | grep -q '^TeamIdentifier=not set'; then \
		printf '\033[33mNote: no Team ID, so the fan helper cannot be installed.\033[0m\n'; \
		printf '\033[33mSign with a Developer ID to enable fan control.\033[0m\n'; \
	fi
	@echo "Built $(BUNDLE)"

run: bundle ## Bundle and launch (kills existing instance first)
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	open $(BUNDLE)

check: bundle ## Typecheck load plugins (ARGS='plugins/foo.js' optional)
	$(BUNDLE)/Contents/MacOS/$(APP_NAME) --check $(ARGS)

release: ## Compile a release binary
	swift build -c release --build-path $(BUILD_DIR)
	@echo "TODO: bundle, sign with Developer ID, notarize, create DMG"

##@ Maintenance

clean: ## Remove build artifacts and the app bundle
	swift package clean --build-path $(BUILD_DIR)
	rm -rf "$(BUNDLE)"

cleanprefs: ## Wipe UserDefaults + Application Support (fresh wizard)
	@killall $(APP_NAME) 2>/dev/null || true
	rm -rf ~/Library/Application\ Support/$(APP_NAME)
	defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@echo "Cleaned preferences and data for $(APP_NAME)"
