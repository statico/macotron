APP_NAME = Macotron
BUILD_DIR = /tmp/macotron-build
BUNDLE = $(HOME)/Applications/$(APP_NAME).app
BUNDLE_ID = io.statico.macotron
CONFIG ?= debug
BINARY = $(BUILD_DIR)/$(CONFIG)/$(APP_NAME)

# Releases are built here, not in CI, so the Developer ID key never leaves this
# Mac. VERSION defaults to the newest tag so local bundles carry a version, but
# release and publish both demand it on the command line: defaulting there would
# happily stamp today's tree with the last tag's number and ship it.
VERSION ?= $(shell git tag --list 'v*' --sort=-v:refname | head -1 | sed 's/^v//')
DMG = $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
# One App Store Connect API key authorizes the whole team, so this profile is
# shared with every other app signed by TA59XVWN77, not specific to Macotron.
NOTARY_PROFILE ?= personal-notary
# A runner has no keychain profile, so CI passes the key file itself instead.
NOTARY_ARGS = $(if $(NOTARY_KEY),--key "$(NOTARY_KEY)" --key-id "$(NOTARY_KEY_ID)" \
	--issuer "$(NOTARY_ISSUER)",--keychain-profile "$(NOTARY_PROFILE)")

# Every release target wants the version spelled out rather than defaulted.
demand-version = test "$(origin VERSION)" = "command line" && test -n "$(VERSION)" || \
	{ echo "usage: make $@ VERSION=x.y.z"; exit 1; }

# Root helper for privileged work such as fan-speed writes. SMAppService loads it
# from inside the bundle, so the plist must use BundleProgram and the helper must
# be signed before the outer bundle is sealed.
HELPER_NAME = MacotronHelper
HELPER_LABEL = $(BUNDLE_ID).helper
HELPER_BINARY = $(BUILD_DIR)/$(CONFIG)/$(HELPER_NAME)

# Stable signing keeps a fixed CDHash, so macOS permissions persist across builds.
# Prefer a Developer ID, which is the only identity that satisfies SMAppService:
# it refuses to register a daemon unless the app and helper share a real Team ID.
# Otherwise fall back to a self-signed Code Signing certificate named Macotron-Dev
# (Keychain Access → Certificate Assistant → Create a Certificate), which keeps
# permissions but cannot install the helper. Last resort is ad-hoc signing,
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
# Ad-hoc is the fallback everywhere, so nested code has one identity to use.
SIGN = $(if $(SIGN_IDENTITY),$(SIGN_IDENTITY),-)

# Sparkle arrives as a prebuilt XCFramework next to the command-line tools that
# sign updates. SwiftPM only unpacks it; embedding and signing are on us.
SPARKLE_DIR = $(BUILD_DIR)/artifacts/sparkle/Sparkle
SPARKLE_FRAMEWORK = $(SPARKLE_DIR)/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework

.DEFAULT_GOAL := help

.PHONY: help version build run bundle check clean cleanprefs release dmg publish tap scan trace

##@ General

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mUsage:\033[0m\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

version: ## Show the installed, released, and working-tree versions
	@printf 'installed  %s\n' "$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
		"$(BUNDLE)/Contents/Info.plist" 2>/dev/null || echo 'not installed')"
	@printf 'released   %s\n' "$$(git tag --list 'v*' --sort=-v:refname | head -1 || true)"
	@printf 'tree       %s\n' "$$(git describe --tags --dirty 2>/dev/null || git rev-parse --short HEAD)"

TRACE_LOG ?= tmp/log

##@ Build

# SWIFT_FLAGS='--disable-sandbox' when make itself runs inside a sandbox:
# SwiftPM cannot nest its own sandbox-exec inside one.
# --disable-keychain: with more than one github.com entry in the login keychain
# SwiftPM hangs forever downloading Sparkle instead of fetching it anonymously.
build: ## Compile the debug binary
	swift build -c $(CONFIG) --build-path $(BUILD_DIR) --disable-keychain $(SWIFT_FLAGS)

bundle: build ## Create ~/Applications/Macotron.app
	@mkdir -p "$(BUNDLE)/Contents/MacOS"
	@mkdir -p "$(BUNDLE)/Contents/Resources"
	@mkdir -p "$(BUNDLE)/Contents/Library/LaunchDaemons"
	@cp $(BINARY) "$(BUNDLE)/Contents/MacOS/$(APP_NAME)"
	@cp $(HELPER_BINARY) "$(BUNDLE)/Contents/MacOS/$(HELPER_NAME)"
	@cp Resources/$(HELPER_LABEL).plist "$(BUNDLE)/Contents/Library/LaunchDaemons/"
	@cp Resources/Info.plist "$(BUNDLE)/Contents/"
	@if [ -n "$(VERSION)" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
			-c "Set :CFBundleVersion $(VERSION)" "$(BUNDLE)/Contents/Info.plist"; \
	fi
	@cp Sources/Macotron/Resources/macotron-runtime.js "$(BUNDLE)/Contents/Resources/"
	@cp Sources/Macotron/Resources/macotron.d.ts "$(BUNDLE)/Contents/Resources/"
	@xcrun actool $(CURDIR)/Resources/$(APP_NAME).icon --compile "$(BUNDLE)/Contents/Resources" \
		--app-icon $(APP_NAME) --output-partial-info-plist $(BUILD_DIR)/icon-partial.plist \
		--platform macosx --minimum-deployment-target 15.0 --errors --warnings >/dev/null
	@cp Resources/banner.png "$(BUNDLE)/Contents/Resources/"
	@mkdir -p "$(BUNDLE)/Contents/Resources/Catalog"
	@/bin/rm -f "$(BUNDLE)/Contents/Resources/Catalog/"*.js
	@cp Resources/Catalog/catalog.json "$(BUNDLE)/Contents/Resources/Catalog/"
	@cp Examples/plugins/*.js "$(BUNDLE)/Contents/Resources/Catalog/"
	@test -d "$(SPARKLE_FRAMEWORK)" || \
		{ echo "Missing $(SPARKLE_FRAMEWORK). Run make build first."; exit 1; }
	@mkdir -p "$(BUNDLE)/Contents/Frameworks"
	@rm -rf "$(BUNDLE)/Contents/Frameworks/Sparkle.framework"
	@ditto "$(SPARKLE_FRAMEWORK)" "$(BUNDLE)/Contents/Frameworks/Sparkle.framework"
	@# Sparkle ships signed by the Sparkle project. Notarization wants our
	@# Developer ID on every binary, and codesign seals nested code first, so
	@# the helpers have to be re-signed before the framework wrapping them.
	@sparkle="$(BUNDLE)/Contents/Frameworks/Sparkle.framework/Versions/B"; \
	test -d "$$sparkle" || { echo "Sparkle.framework has no Versions/B."; exit 1; }; \
	for nested in "$$sparkle"/XPCServices/*.xpc "$$sparkle/Updater.app" "$$sparkle/Autoupdate"; do \
		[ -e "$$nested" ] || continue; \
		codesign --force --sign "$(SIGN)" $(SIGN_FLAGS) "$$nested"; \
	done; \
	codesign --force --sign "$(SIGN)" $(SIGN_FLAGS) \
		"$(BUNDLE)/Contents/Frameworks/Sparkle.framework"
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
		printf '\033[33mNote: no Team ID, so the helper cannot be installed.\033[0m\n'; \
		printf '\033[33mSign with a Developer ID to enable fan control.\033[0m\n'; \
	fi
	@echo "Built $(BUNDLE)"

run: bundle ## Bundle and launch (kills existing instance first)
	@killall $(APP_NAME) 2>/dev/null || true
	@sleep 0.3
	open $(BUNDLE)

check: bundle ## Typecheck load plugins (ARGS='plugins/foo.js' optional)
	$(BUNDLE)/Contents/MacOS/$(APP_NAME) --check $(ARGS)

# Tees to $(TRACE_LOG) because `log` refuses to run inside a sandbox: an agent
# working in one can read the file even though it cannot run the command.
# Macotron logs to the unified log, which `log show` can read back but a
# sandboxed process cannot -- hence the tee. Same command as the one in the
# bug report template, for people without a checkout.
trace: ## Stream the app log to the terminal and tmp/log
	@mkdir -p $(dir $(TRACE_LOG))
	log stream --level info --style compact --predicate 'subsystem == "io.statico.macotron"' \
		| tee $(TRACE_LOG)

scan: ## Sweep built-in plugins + tmp/malware with the on-device scanner
	swift run --build-path $(BUILD_DIR) PluginScan --runs $${SCAN_RUNS:-3} --concurrency $${SCAN_CONCURRENCY:-16} \
		Examples/plugins --fail tmp/malware --out tmp/scan-sweep.jsonl $(ARGS)

release: ## Tag, build, and ship a release + Homebrew cask (VERSION=x.y.z)
	@$(demand-version)
	@test -n "$(ALLOW_UNNOTARIZED)" || git diff --quiet HEAD || \
		{ echo "Working tree is dirty."; exit 1; }
	@# Whatever is about to be tagged has to be what everyone else can see.
	@test -n "$(ALLOW_UNNOTARIZED)" || { \
		git fetch --quiet origin main && \
		test -z "$$(git rev-list origin/main..HEAD)" -a -z "$$(git rev-list HEAD..origin/main)"; \
	} || { echo "main and origin/main have diverged. Push or pull first."; exit 1; }
	@$(MAKE) dmg VERSION=$(VERSION)
	@# An unnotarized DMG is a local test build; nobody should download it.
	@if [ -n "$(ALLOW_UNNOTARIZED)" ]; then echo "Not published: ALLOW_UNNOTARIZED."; else \
		$(MAKE) publish VERSION=$(VERSION); \
	fi

dmg: ## Build, sign, and notarize the DMG only (VERSION=x.y.z)
	@$(demand-version)
	@git tag --list 'v$(VERSION)' | grep -q . && \
		{ echo "v$(VERSION) already exists."; exit 1; } || true
	@mkdir -p $(BUILD_DIR)
	@prev=$$(git tag --list 'v*' --sort=-v:refname | head -1); \
		if [ -n "$$prev" ]; then \
			git log --reverse --no-merges --pretty='- %s' $$prev..HEAD \
				> $(BUILD_DIR)/notes.md; \
		else \
			echo "- First release." > $(BUILD_DIR)/notes.md; \
		fi
	@echo "Release notes:"; sed 's/^/  /' $(BUILD_DIR)/notes.md
	@$(MAKE) CONFIG=release VERSION=$(VERSION) bundle
	@codesign -dvv "$(BUNDLE)" 2>&1 | grep -q "Authority=Developer ID" || \
		{ echo "Refusing to package: not signed with a Developer ID."; exit 1; }
	@rm -rf $(BUILD_DIR)/dmg && mkdir -p $(BUILD_DIR)/dmg
	@cp -R "$(BUNDLE)" $(BUILD_DIR)/dmg/
	@ln -s /Applications $(BUILD_DIR)/dmg/Applications
	@rm -f "$(DMG)"
	@hdiutil create -quiet -volname "$(APP_NAME) $(VERSION)" \
		-srcfolder $(BUILD_DIR)/dmg -ov -format UDZO "$(DMG)"
	@codesign --force --sign "$(SIGN_IDENTITY)" "$(DMG)"
	@if err=$$(xcrun notarytool history $(NOTARY_ARGS) 2>&1); then \
		xcrun notarytool submit "$(DMG)" $(NOTARY_ARGS) --wait && \
		xcrun stapler staple "$(DMG)"; \
	elif [ -n "$(ALLOW_UNNOTARIZED)" ]; then \
		printf '\033[33mUnnotarized: this DMG is only good for local testing.\033[0m\n'; \
	else \
		echo "$$err" | sed 's/^/  /'; \
		echo "Notarization credentials do not work. Gatekeeper would tell everyone"; \
		echo "who downloads this that Macotron is malware, so refusing to package it."; \
		echo "See docs/releasing.md, or ALLOW_UNNOTARIZED=1 to test locally."; \
		rm -f "$(DMG)"; \
		exit 1; \
	fi
	@if [ -z "$(ALLOW_UNNOTARIZED)" ]; then xcrun stapler validate "$(DMG)"; fi
	@echo "Built $(DMG)"

publish: ## Appcast, tag, GitHub release, and cask for a built DMG (VERSION=x.y.z)
	@$(demand-version)
	@test -f "$(DMG)" || { echo "No $(DMG). Run make dmg first."; exit 1; }
	@# The appcast has to be signed after stapling, which rewrites the DMG, and
	@# committed before the tag so the tag matches what the feed describes. The
	@# branch is pushed last because that deploys the feed, and a feed that
	@# names a DMG GitHub has not finished uploading is a 404 for everyone.
	@set -x; \
	SPARKLE_DIR=$(SPARKLE_DIR) scripts/update-appcast.sh $(VERSION) "$(DMG)" $(BUILD_DIR)/notes.md && \
	git add site/appcast.xml && \
	git commit -qm "Appcast for $(VERSION)" -- site/appcast.xml && \
	git tag -a v$(VERSION) -m "$(APP_NAME) $(VERSION)" && \
	git push origin v$(VERSION) && \
	gh release create v$(VERSION) "$(DMG)" --title "$(APP_NAME) $(VERSION)" \
		--notes-file $(BUILD_DIR)/notes.md && \
	git push origin HEAD && \
	scripts/update-tap.sh $(VERSION) "$(DMG)"

tap: ## Re-point the Homebrew cask at VERSION (release does this already)
	@$(demand-version)
	scripts/update-tap.sh $(VERSION) "$(DMG)"

##@ Maintenance

clean: ## Remove build artifacts and the app bundle
	swift package clean --build-path $(BUILD_DIR)
	rm -rf "$(BUNDLE)"

cleanprefs: ## Wipe UserDefaults + Application Support (fresh wizard)
	@killall $(APP_NAME) 2>/dev/null || true
	rm -rf ~/Library/Application\ Support/$(APP_NAME)
	defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@echo "Cleaned preferences and data for $(APP_NAME)"
