# iOS launch

Goal: the app matches vomatt-web `main` in behavior and the "Vomatt iOS Design" canvas
(claude.ai artifact Q5QSgMjVneZXqg22MiPbCs) in structure, and is ready for App Review.

Done means: `make test-core` and `make build` pass; `make sync-check` passes against web `main`;
every stage below is observed in the simulator against a local API (`.claude/skills/verify`);
the release checklist's code items are ticked, and the rest name who has to do them.

One PR per stage, stacked in this order. Each stage ends green before the next starts.

## Stage 1: Sync with web main
**Goal**: Contract, strings, avatars and tokens from web `main`; the app compiles and shows no raw keys.
**Success Criteria**: `make test-core` (now includes `scripts/check-strings.py`) and `make build` pass.
**Tests**: `PollTimingTests` (port of `timing.test.ts`); the string-key check.
**Status**: Complete (`6f12790`)

## Stage 2: Activity
**Goal**: An Activity tab built on `GET /api/notifications`: six kinds (result, cancelled, invitation,
followed, comment, closing soon), All/Unread, Today/Yesterday/Earlier sections, mark one read on open,
Mark all read, Follow back on follow rows, the design's empty state. The tab's unread mark clears.
**Success Criteria**: Every kind renders; opening a row marks it read; the badge falls to 0 after
Mark all read; `notifications.*` strings from the web.
**Tests**: Service tests for list/markRead/readAll with fixtures; a domain test for day grouping.
**Status**: Not Started

## Stage 3: Profile and Settings
**Goal**: Own profile with Asked/Voted tabs and filters (drafts under Asked, "only you"), stats,
follower/following counts; Settings as its own screen. The My Polls tab goes away (Activity replaces it).
**Success Criteria**: Everything My Polls showed is reachable from Profile or Activity.
**Tests**: Ports of the web's profile filter logic into `VomattCoreTests`.
**Status**: Not Started

## Stage 4: People and safety
**Goal**: Visitor profile (counts, "follows you", mutual followers, Follow back, ••• with Share,
Copy link, Block with confirm); follow lists with per-row buttons; comment reports through the API;
share tracking (`POST /votes/{id}/share`).
**Success Criteria**: A comment report reaches the API; blocking asks first.
**Tests**: Service tests for each new endpoint.
**Status**: Not Started

## Stage 5: Settings parity
**Goal**: Notification preference switches, passkeys (sign in, add, remove; `webcredentials` entitlement),
`common.conflict` shown as busy, the design's grouped Settings and Edit profile.
**Tests**: Service tests for preferences and passkeys.
**Status**: Not Started

## Stage 6: Poll, create, home, explore to the design
**Goal**: Poll action footer and Seal, results summary, Discussion "See all", create sheet (duration chips,
rules card, "Review as a voter"), Home and Explore layouts.
**Status**: Not Started

## Stage 7: Release
**Goal**: Docs current (`release-checklist.md`, `backend-requests.md`), version bump, end-to-end run of the
TestFlight smoke list in the simulator. Hand back what needs a person: Apple team ID, App Store Connect,
`IOS_APP_IDS` on Vercel, push (no device-registration API yet).
**Status**: Not Started
