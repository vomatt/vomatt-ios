# Release checklist (iOS)

## Decide before the first build

- [x] **Bundle ID**: `com.vomatt.app` (`VOMATT_BUNDLE_ID`)
- [ ] **Apple Developer team ID**: set `VOMATT_DEVELOPMENT_TEAM` (in `Configs/Local.xcconfig` or
      `Shared.xcconfig`) and `IOS_APP_IDS=<TEAMID>.com.vomatt.app` on vomatt-web
- [x] **Production API origin**: `https://vomatt-api-production.up.railway.app` (`VOMATT_API_URL`)
- [x] **Site origin**: `https://vomatt.com` (`VOMATT_SITE_URL`): share links and universal links
- [x] **Support email**: `team@vomatt.com` (`VOMATT_SUPPORT_EMAIL`): content reports and
      "Contact us" go there
- [x] **Terms and privacy URLs**: the app links `<site>/terms-of-service`, `<site>/privacy-policy`
      and the cookies page (`LegalLinks` in `Features/Profile/SettingsView.swift`, also on the
      signed-out Profile tab), the live Sanity page slugs (checked 2026-10-17)

## Backend and web

- [x] The deployed API runs the contract in `openapi.json` (`make api-diff API_URL=…` shows nothing; checked 2026-10-17)
- [ ] Universal links: vomatt-web serves `/.well-known/apple-app-site-association` once
      `IOS_APP_IDS` is set on Vercel; the entitlement already lists `applinks:vomatt.com`.
      Until then `vomatt://poll/<id>` works.
- [x] Content moderation (App Review guideline 1.2): people can report a poll or a comment through
      the API, and block a user from a profile, a poll or a comment (it asks first); the API hides
      the blocked person's polls and comments, and Settings lists them to unblock.
- [ ] Someone reads reports within 24 hours (Apple's expectation): name who, and where they look

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

- [x] Version: `1.0.0` (build `1`) in `project.yml` for the first upload; raise
      `CURRENT_PROJECT_VERSION` for every later upload, `MARKETING_VERSION` for every release
- [ ] `make test` and `make test-ui` pass (the signed-in flow against `scripts/e2e-api.sh`, see
      docs/e2e.md); `make sync-check` passes
- [ ] `make archive` (uploads to App Store Connect with `Configs/ExportOptions.plist`)
- [ ] TestFlight smoke test on a device: sign up, sign out, sign in (code and passkey), vote, change
      vote, withdraw, comment, reply, like, report a comment and a poll, save a poll, create a poll
      (public and invite-only, with an invite list), edit while scheduled, delete, follow and block
      someone from their profile, read and mark all notifications read, the Asked and Voted filters,
      edit profile with a hidden field, change avatar, switch the theme, delete a throwaway account

## Already in place

- Account deletion in the app (Settings → Delete account), guideline 5.1.1(v)
- Privacy manifest with the UserDefaults reason (drafts)
- Tokens in the Keychain, this device only; no third-party SDKs, no tracking
- App icon (light, dark, tinted), launch screen in the canvas color
- Dynamic Type through `Font.custom(_:size:relativeTo:)`, VoiceOver labels, Reduce Motion for the
  skeleton shimmer, 44pt touch targets, light and dark mode from the web's tokens

## Known gaps (need the API or a decision; specs in [backend-requests.md](backend-requests.md))

- Push notifications: the API has no device-token registration, so unread Invitations and results
  show as the dot on the Notifications tab, refreshed when the app becomes active
- Sign in with Apple: the API has `/api/auth/apple`; wiring it needs the Apple service ID configured
  on the API (`APPLE_CLIENT_ID`) to accept this app's bundle ID
- Signed-out blocks stay on the device and move to the account at sign-in
