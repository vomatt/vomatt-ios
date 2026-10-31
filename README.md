# vomatt for iOS

The native iPhone and iPad app for vomatt, the public voting platform. It is built from
[vomatt-web](../vomatt-web): the same design tokens, strings, avatars, poll rules and API
contract, in SwiftUI.

| | |
|---|---|
| UI | SwiftUI, iOS 17+, iPhone and iPad |
| API | [vomatt-api](../vomatt-api), through a client generated from `openapi.json` at build time ([swift-openapi-generator](https://github.com/apple/swift-openapi-generator)) |
| Shared with the web | API contract, `en`/`zh` strings, color tokens, the 72 bot avatars, the Geist fonts, poll rules |
| Project | [XcodeGen](https://github.com/yonaskolb/XcodeGen) generates `Vomatt.xcodeproj` from `project.yml` |

## Getting started

Needs Xcode 26 or later and Homebrew.

```bash
make bootstrap   # installs XcodeGen, generates Vomatt.xcodeproj
make open        # opens it in Xcode
```

The first build asks you to **Trust & Enable** the `OpenAPIGenerator` plugin; it generates the API
client from `openapi.json`. Pick a simulator and run.

Signing: create `Configs/Local.xcconfig` (git ignores it) with your team:

```
VOMATT_DEVELOPMENT_TEAM = ABCDE12345
```

If `xcode-select -p` points at the Command Line Tools, the Makefile still finds Xcode through
`DEVELOPER_DIR`. Xcode's own tools (and the simulator integrations) want it switched once:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

## Commands

| Command | What it does |
|---|---|
| `make test-core` | `scripts/check-strings.py`, then the domain, networking and contract tests in `Packages/VomattKit` (seconds, no simulator) |
| `make build` | Builds the app for a simulator (`SIMULATOR="iPhone 17"` by default) |
| `make test-ui` | UI smoke tests against the configured API |
| `make test` | What CI runs: `test-core` and `build` |
| `make sync` | Pulls the strings, color tokens and avatars from `../vomatt-web`'s `origin/main` (`WEB_REF`), and the API contract from `../vomatt-api`'s (`API_REF`) |
| `make sync-check` | Fails when any of those differ from it |
| `make api-diff API_URL=https://…` | Compares `openapi.json` with what a deployed API serves |
| `make archive` | Release archive and App Store Connect upload (needs signing) |

## Configuration

Per-configuration values live in `Configs/*.xcconfig` and reach the app through Info.plist:

| Setting | Debug | Release |
|---|---|---|
| `VOMATT_API_URL` | `https://vomatt-api-production.up.railway.app` | `https://vomatt-api-production.up.railway.app` |
| `VOMATT_SITE_URL` | `https://vomatt.com` | `https://vomatt.com` (share links, universal links) |
| `VOMATT_LOG_REQUESTS` | `YES` (one console line per request, no bodies or tokens) | `NO` |
| `VOMATT_BUNDLE_ID` | `com.vomatt.app` | |

Against a vomatt-api on this Mac, put this in `Configs/Local.xcconfig`
(xcconfig reads `//` as a comment, hence `$(SLASH)`):

```
VOMATT_API_URL = http:$(SLASH)$(SLASH)localhost:8080
```

## How it fits together

```
App/                      SwiftUI app (MainActor by default)
  AppModel.swift          session, signed-in user, language, navigation, toasts, poll cache
  DesignSystem/           the web's DESIGN.md: tokens, type, Button, fields, chips, cards, tabs
    Tokens.generated.swift  generated from vomatt-web global.css (scripts/sync.sh tokens)
  Features/               Auth, Polls (card, ballot, results, comments), Creator, Lists, Profile
  Resources/              Colors, Avatars (generated), Assets, Locales (copied), Fonts, privacy manifest
Packages/VomattKit/
  Sources/VomattAPI/      openapi.json + generator config; the client is generated at build time
  Sources/VomattCore/     domain models, poll rules, service, session/refresh, i18n, formatting
  Tests/VomattCoreTests/  ports of the web's tests, plus contract and session tests
scripts/                  sync.sh, api-diff.py, tokens.py, svg_oklch.py, check-strings.py, e2e-api.sh, e2e-otp.py
UITests/                  smoke tests, and the signed-in E2E flow (docs/e2e.md)
```

The layers mirror the web:

| Web | iOS |
|---|---|
| `features/polls/schema.ts` (zod) | `VomattCore/Models` + `Networking/Mapping.swift` (generated types → domain) |
| `features/*/service.ts`, `lib/api/services/*` | `VomattCore/VomattService.swift` |
| `features/polls/status.ts`, `account/insights.ts` | `VomattCore/Domain/PollStatus.swift`, `Insights.swift` |
| `lib/api/tokens.ts` + `proxy.tsx` (single refresh) | `VomattCore/Networking/Session.swift` + `AuthMiddleware` |
| `contexts/LanguageContext.tsx` + `locales/*.json` | `VomattCore/I18n/Localizer.swift` reading the same JSON |
| `components/ui/*`, `DESIGN.md` | `App/DesignSystem/*` |

Each screen ports a web feature; port behavior (and its tests) from the web file on the left:

| Screen | Web (`src/…`) | iOS |
|---|---|---|
| Home, Explore | `app/(frontend)/page.tsx`, `explore/_components/ExploreView.tsx` | `Features/Lists/HomeView.swift`, `ExploreView.swift` |
| Poll card, poll page | `features/polls/components/PollCard.tsx`, `Ballot.tsx`, `Results.tsx`, `app/(frontend)/poll/[id]` | `Features/Polls/*` |
| Create | `features/polls/components/PollCreator` | `Features/Creator/*` |
| Notifications tab | `features/notifications/NotificationList.tsx`, `NotificationRows.tsx` | `Features/Lists/NotificationsView.swift` |
| Your profile (Asked, Voted) | `app/(frontend)/[slug]/_components/OwnProfileView.tsx` | `Features/Profile/AccountView.swift` |
| Someone's profile | `…/VisitorProfileView.tsx` | `Features/Profile/ProfileView.swift` |
| Settings | `app/(frontend)/settings` | `Features/Profile/SettingsView.swift` |
| Sign in | `app/(frontend)/login` | `Features/Auth/*` |

Tokens live in the Keychain (this device only). The backend rotates the refresh token and revokes
every session when a used one comes back, so `Session` refreshes single-flight and saves the new pair
before anyone uses it, like the web's proxy.

### Liquid Glass

`DESIGN.md` rules out glass and backdrop blur. iOS makes one exception: on iOS 26 and later the
**system chrome** (the tab bar and navigation bars) uses the platform's Liquid Glass, because that is
how native chrome looks and Apple handles Reduce Transparency, contrast and dark mode for it.

- `RootView` uses the system `TabView`, which floats and shrinks while scrolling down. Create is a
  tab that opens the creator instead of being selected.
- iOS 17–25 keep the flat `VMTabBar` from the web's `TabBar`.
- Content stays flat: no `.glassEffect()`, materials or blur on cards, sheets or the creator's
  bottom bar, and no custom toolbar backgrounds.

## Keeping up with the API

See [docs/api-sync.md](docs/api-sync.md). In short: `scripts/sync.sh api` prints what changed in the
contract, then the build regenerates the client and the compiler points at every place to update.

## Releasing

See [docs/release-checklist.md](docs/release-checklist.md).
