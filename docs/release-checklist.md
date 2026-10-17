# Release checklist (iOS)

## Decide before the first build

- [x] **Bundle ID**: `com.vomatt.app` (`VOMATT_BUNDLE_ID`)
- [ ] **Apple Developer team ID**: set `VOMATT_DEVELOPMENT_TEAM` (in `Configs/Local.xcconfig` or
      `Shared.xcconfig`) and `IOS_APP_IDS=<TEAMID>.com.vomatt.app` on vomatt-web
- [x] **Production API origin**: `https://vomatt-api.vercel.app` (`VOMATT_API_URL`)
- [x] **Site origin**: `https://vomatt.com` (`VOMATT_SITE_URL`): share links and universal links
- [ ] **Support email** (`VOMATT_SUPPORT_EMAIL`, from the API contract): content reports and
      "Contact us" go there
- [ ] **Terms and privacy URLs**: the app links `<site>/terms` and `<site>/privacy`
      (`AppSettingsSection` in `Features/Profile/AccountView.swift`); match the Sanity page slugs

## Backend and web

- [x] The deployed API runs the contract in `openapi.json` (`make api-diff API_URL=…` shows nothing; checked 2026-10-17)
- [ ] Universal links: vomatt-web serves `/.well-known/apple-app-site-association` once
      `IOS_APP_IDS` is set on Vercel; the entitlement already lists `applinks:vomatt.com`.
      Until then `vomatt://poll/<id>` works.
- [ ] Content moderation (App Review guideline 1.2): the app lets people report a poll or comment by
      email. A report endpoint and blocking users need the API (see "Known gaps").

## App Store Connect

- [ ] App record, name "vomatt", primary language English, Traditional Chinese localization
- [ ] Privacy nutrition label, matching `App/Resources/PrivacyInfo.xcprivacy`: email address, name
      (display name), user ID, other user content (polls, votes, comments); all linked to the user,
      none used for tracking
- [ ] Age rating questionnaire (user-generated content, unrestricted web access: no)
- [ ] Review notes: sign-in is an emailed one-time code; give the reviewer a mailbox they can read,
      or a demo account the API accepts
- [ ] Screenshots: 6.9" iPhone and 13" iPad, light mode, `en` and `zh-Hant`
- [ ] Export compliance: `ITSAppUsesNonExemptEncryption` is `NO` (HTTPS only)

## Build and ship

- [ ] Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`
- [ ] `make test` and `make test-ui` pass; `make sync-check` passes
- [ ] `make archive` (uploads to App Store Connect with `Configs/ExportOptions.plist`)
- [ ] TestFlight smoke test on a device: sign up, sign out, sign in, vote, change vote, withdraw,
      comment, reply, like, create a poll (public and invite-only), edit while scheduled, delete,
      edit profile, change avatar, toggle visibility, switch language, delete a throwaway account

## Already in place

- Account deletion in the app (Settings → Delete account), guideline 5.1.1(v)
- Privacy manifest with the UserDefaults reason (drafts, language)
- Tokens in the Keychain, this device only; no third-party SDKs, no tracking
- App icon (light, dark, tinted), launch screen in the canvas color
- Dynamic Type through `Font.custom(_:size:relativeTo:)`, VoiceOver labels, Reduce Motion for the
  skeleton shimmer, 44pt touch targets, light and dark mode from the web's tokens

## Known gaps (need the API or a decision)

- Push notifications: the API has no device-token registration, so unread Invitations and results
  show as the dot on My Polls, refreshed when the app becomes active
- Sign in with Apple: the API has `/api/auth/apple`; wiring it needs the Apple service ID configured
  on the API (`APPLE_CLIENT_ID`) to accept this app's bundle ID
- Follows: hidden on the web too until the API supports them
- Reporting and blocking users: reports go by email today
