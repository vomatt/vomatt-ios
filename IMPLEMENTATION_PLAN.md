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
**Goal**: Notifications become the Activity tab (bell, Alert dot) in place of My Polls, with the design's
All/Unread toggle, Today/Yesterday/Earlier sections and empty state. The feed, mark read, Mark all read
and Follow back already landed on main (#23); this stage moves and reshapes it.
**Success Criteria**: Activity is a tab; the badge falls to 0 after Mark all read.
**Tests**: A domain test for day grouping.
**Status**: Not Started

## Stage 3: Profile and Settings
**Goal**: Own profile with Asked/Voted tabs and filters (drafts under Asked, "only you"), stats,
follower/following counts; Settings as its own screen. The My Polls tab goes away (Activity replaces it).
**Success Criteria**: Everything My Polls showed is reachable from Profile or Activity.
**Tests**: Ports of the web's profile filter logic into `VomattCoreTests`.
**Status**: Not Started

## Stage 4: People and safety
**Goal**: Visitor profile to the design: full-width Follow / Follow back, ••• menu with Share profile,
Copy link and Block with a confirm step. Counts, mutuals, comment reports and share tracking already
landed on main (#21–#23).
**Success Criteria**: Blocking asks first; the menu works from a visitor profile.
**Status**: Not Started

## Stage 5: Settings parity
**Goal**: The design's grouped Settings and Edit profile; `common.conflict` shown as busy. Notification
switches and passkeys already landed on main (#22, #23).
**Tests**: The conflict override in `I18nTests`.
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
