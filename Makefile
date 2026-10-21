# Day-to-day commands. Xcode is selected through DEVELOPER_DIR, so this works even
# when `xcode-select` points at the Command Line Tools.
DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
SIMULATOR ?= iPhone 17
DESTINATION = platform=iOS Simulator,name=$(SIMULATOR)
# The OpenAPI generator runs as a build plugin; in Xcode, trust it once when asked
XCODEBUILD = xcodebuild -project Vomatt.xcodeproj -scheme Vomatt -skipPackagePluginValidation

.PHONY: bootstrap project test test-core test-ui build formal sync sync-check api-diff archive open clean

bootstrap: ## Install XcodeGen and generate the project
	@command -v xcodegen >/dev/null || brew install xcodegen
	$(MAKE) project

project: ## Regenerate Vomatt.xcodeproj from project.yml
	xcodegen generate --quiet

open: project
	open Vomatt.xcodeproj

test-core: ## Domain, networking and API contract tests (fast, no simulator)
	cd Packages/VomattKit && swift test

build: project ## Build the app for the simulator
	$(XCODEBUILD) -destination '$(DESTINATION)' -quiet build

test-ui: project ## UI smoke tests in the simulator
	$(XCODEBUILD) -destination '$(DESTINATION)' -quiet test

test: test-core build ## Everything CI runs

formal: ## Model-check the Session refresh with TLC (.claude/skills/verify-session-refresh)
	Formal/check-session.sh

sync: ## Pull the API contract, strings, color tokens and avatars from ../vomatt-web
	scripts/sync.sh all

sync-check: ## Fail when anything differs from ../vomatt-web
	scripts/sync.sh check

api-diff: ## Compare the contract with the deployed API (API_URL=https://...)
	@test -n "$(API_URL)" || (echo "Set API_URL, e.g. make api-diff API_URL=https://vomatt-api-production.up.railway.app" && exit 1)
	curl -fsSL "$(API_URL)/v3/api-docs" -o /tmp/vomatt-live-api.json
	python3 scripts/api-diff.py Packages/VomattKit/Sources/VomattAPI/openapi.json /tmp/vomatt-live-api.json

archive: project ## Release archive for App Store Connect (needs a signing team in Configs/Local.xcconfig)
	$(XCODEBUILD) -configuration Release -destination 'generic/platform=iOS' -archivePath build/Vomatt.xcarchive archive
	xcodebuild -exportArchive -archivePath build/Vomatt.xcarchive -exportOptionsPlist Configs/ExportOptions.plist -exportPath build/export

clean:
	rm -rf build Vomatt.xcodeproj Packages/VomattKit/.build
