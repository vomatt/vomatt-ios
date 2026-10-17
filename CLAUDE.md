# CLAUDE.md

Guidance for Claude Code in this repository.

## What this is

The native iOS app for vomatt (SwiftUI, iOS 17+). It is a port of `../vomatt-web` and shares its
API contract, strings, color tokens, avatars, fonts and poll rules. Read `README.md` for the layout
and `../vomatt-web/DESIGN.md` + `../vomatt-web/PRODUCT.md` before any UI work: the iOS design
system in `App/DesignSystem/` follows them.

## Commands

```bash
make project      # regenerate Vomatt.xcodeproj from project.yml (never edit the .xcodeproj)
make test-core    # Packages/VomattKit tests: domain, networking, contract (swift test, seconds)
make build        # simulator build; SIMULATOR="iPhone 17" by default
make test-ui      # UI smoke tests (E2E against a local API: docs/e2e.md)
make sync-check   # contract, strings, avatars still match ../vomatt-web
```

`DEVELOPER_DIR` is set by the Makefile, so it works while `xcode-select` points at the CLT.
Command-line `xcodebuild` needs `-skipPackagePluginValidation` (the Makefile passes it).

## Rules

- **The API contract is generated.** `Packages/VomattKit/Sources/VomattAPI/openapi.json` is synced
  from vomatt-web/vomatt-api with `scripts/sync.sh api` (docs/api-sync.md). Only
  `Networking/Mapping.swift` and `VomattService.swift` touch generated types; the app sees domain
  models from `VomattCore/Models`.
- **Never refresh tokens outside `Session`.** The backend ends the sign-in when a used refresh token
  comes back; `Session` is single-flight and saves the rotated pair first.
- **Strings come from the web.** `App/Resources/Locales/en.json`/`zh.json` are copies: change them
  in vomatt-web and run `scripts/sync.sh locales`. iOS-only keys go in `ios.en.json`/`ios.zh.json`.
- **Colors come from the web.** Use `Tokens.*` (generated from `global.css` by `scripts/sync.sh
  tokens`); no raw colors, no new one-off tokens. Volt is only for the viewer's own choice and unread.
- **Building blocks**: `VMButtonStyle` (`.vm(...)`), `fieldChrome`, `VMTextField`, `Chip`,
  `StatusChip`, `EmptyState`, `UnreadDot`, `LineTabs`, `PollRow`, `.card()`. Don't restyle at the
  call site; add a variant.
- **No live counts while a poll is open** (sealed ballots); status is never shown by color alone.
- The app target is MainActor by default (`SWIFT_DEFAULT_ACTOR_ISOLATION`); value types used off the
  main actor (shapes, geometry effects, the language box) are marked `nonisolated`.
- Port behavior from the web feature it mirrors (the table in README.md), and port its tests into
  `Packages/VomattKit/Tests` when the logic lives in VomattCore.
