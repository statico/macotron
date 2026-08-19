APP_NAME = Macotron
BUILD_DIR = /tmp/macotron-build
BUNDLE = $(HOME)/Applications/$(APP_NAME).app
BINARY = $(BUILD_DIR)/debug/$(APP_NAME)
BUNDLE_ID = io.statico.macotron

# Stable signing keeps a fixed CDHash, so macOS permissions persist across builds.
# Create the certificate in Keychain Access → Certificate Assistant → Create a
# Certificate → Code Signing, and name it Macotron-Dev. Set SIGN_IDENTITY by hand
# to use a different one. Falls back to ad-hoc signing, which resets permissions
# on every build.
#
# A self-signed certificate is untrusted, so it is missing from `find-identity -v`
# even though codesign accepts it. Match on the name instead, and skip anything
# expired because codesign does reject those.
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning 2>/dev/null | \
	grep -v CSSMERR_TP_CERT_EXPIRED | grep -m1 -o '"Macotron-Dev[^"]*"' | tr -d '"')

.DEFAULT_GOAL := help

.PHONY: help build run bundle check clean cleanprefs dev reload eval health snippets commands release

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
	@cp $(BINARY) "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/"
	@cp Sources/Macotron/Resources/macotron-runtime.js "$(BUNDLE)/Contents/Resources/"
	@cp Sources/Macotron/Resources/macotron.d.ts "$(BUNDLE)/Contents/Resources/"
	@xcrun actool $(CURDIR)/Resources/$(APP_NAME).icon --compile "$(BUNDLE)/Contents/Resources" \
		--app-icon $(APP_NAME) --output-partial-info-plist $(BUILD_DIR)/icon-partial.plist \
		--platform macosx --minimum-deployment-target 15.0 --errors --warnings >/dev/null
	@cp Resources/banner.png "$(BUNDLE)/Contents/Resources/"
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		codesign --force --sign "$(SIGN_IDENTITY)" --entitlements Resources/Macotron.entitlements "$(BUNDLE)"; \
		echo "Signed with $(SIGN_IDENTITY)"; \
	else \
		codesign --force --sign - --entitlements Resources/Macotron.entitlements "$(BUNDLE)"; \
		printf '\033[33mWarning: ad-hoc signed. macOS permissions reset on every build.\033[0m\n'; \
		printf '\033[33mCreate a Code Signing certificate in Keychain Access to keep them.\033[0m\n'; \
	fi
	@echo "Built $(BUNDLE)"

run: bundle ## Bundle and launch (kills existing instance first)
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	open $(BUNDLE)

check: bundle ## Typecheck load plugins (ARGS='plugins/foo.js' optional)
	$(BUNDLE)/Contents/MacOS/$(APP_NAME) --check $(ARGS)

dev: bundle ## Bundle and run with debug server on :7777
	$(BUNDLE)/Contents/MacOS/$(APP_NAME) --debug-server

release: ## Compile a release binary
	swift build -c release --build-path $(BUILD_DIR)
	@echo "TODO: bundle, sign with Developer ID, notarize, create DMG"

##@ Debug server (make dev)

reload: ## Hot-reload plugins
	@curl -s -X POST http://localhost:7777/reload

eval: ## Eval JS (JS='macotron.notify.show("hi","there")')
	@curl -s -X POST http://localhost:7777/eval \
		-H "Content-Type: application/json" \
		-d '{"js": "$(JS)"}'

health: ## Show debug server health JSON
	@curl -s http://localhost:7777/health | python3 -m json.tool

snippets: ## List loaded plugins (legacy endpoint name)
	@curl -s http://localhost:7777/snippets | python3 -m json.tool

commands: ## List registered launcher commands
	@curl -s http://localhost:7777/commands | python3 -m json.tool

##@ Maintenance

clean: ## Remove build artifacts and the app bundle
	swift package clean --build-path $(BUILD_DIR)
	rm -rf "$(BUNDLE)"

cleanprefs: ## Wipe UserDefaults + Application Support (fresh wizard)
	@killall $(APP_NAME) 2>/dev/null || true
	rm -rf ~/Library/Application\ Support/$(APP_NAME)
	defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@echo "Cleaned preferences and data for $(APP_NAME)"
