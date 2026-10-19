---
name: verify
description: Run the vomatt iOS app in the simulator against a throwaway local API and drive it with a temporary XCUITest driver to observe a change.
---

# Verifying vomatt-ios changes at runtime

The Claude simulator panel needs `xcode-select` on full Xcode; it often points at the CLT. Drive the
app with a temporary XCUITest instead (`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`).

1. **Local API, no real email** (docs/e2e.md step 1). Docker is OrbStack: `open -a OrbStack` if
   `docker info` fails. The `vomatt-api-local` image is usually already built.
2. **Codes + network control**: a host loop copies `otp:email:*` codes from `vomatt-ios-redis` into a
   folder, and runs `docker pause/unpause vomatt-api-local` when the driver drops flag files. The
   simulator shares the host filesystem, so the driver reads and writes those paths directly. Pausing
   the API is how to see loading states; local requests are too fast otherwise.
3. `echo 'VOMATT_API_URL = http:$(SLASH)$(SLASH)localhost:8080' > Configs/Local.xcconfig`
4. Add `UITests/VerifyDriver.swift` (skips unless `VERIFY_DIR` is set). Launch with
   `-preferred-language en -reset-session`, save screenshots with
   `XCUIScreen.main.screenshot().pngRepresentation.write(to:)`, and log observations to a file.
5. `xcodegen generate --quiet`, then
   `TEST_RUNNER_VERIFY_DIR=<dir> xcodebuild -project Vomatt.xcodeproj -scheme Vomatt -skipPackagePluginValidation -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:VomattUITests/VerifyDriver test`
6. Clean up: delete the driver and `Configs/Local.xcconfig`, run `xcodegen generate`, stop the loop,
   and `docker rm -f vomatt-api-local vomatt-ios-pg vomatt-ios-redis`.

Gotchas: the API's 3rd wrong code returns `auth.otp.too_many_attempts`. A fresh DB has no polls, so
start sign-in from the "Create a poll" tab. To change the email after "Use a different email", run a
new launch rather than clearing the field (select-all is unreliable).
