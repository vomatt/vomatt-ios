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

## Stage 2: Notifications tab
**Goal**: Notifications become a tab (bell, Alert dot) in place of My Polls, ported from the web's
`NotificationList`: All/Unread pills, Today/Yesterday/Earlier sections, folded follows, per-row actions.
The tab keeps the web's word, Notifications, so the strings stay shared. My Polls is reachable from
Profile until Stage 3 folds it in.
**Success Criteria**: Notifications is a tab; the badge clears after Mark all read (observed in the simulator).
**Tests**: `ActivityTests` (port of the web's day grouping, follow folding, age, plural counts).
**Status**: Complete

## Stage 3: Profile and Settings
**Goal**: Own profile with Asked/Voted tabs and filters (drafts under Asked, "only you"), stats,
follower/following counts; Settings as its own screen. The My Polls tab goes away (Activity replaces it).
**Success Criteria**: Everything My Polls showed is reachable from Profile or Notifications.
**Tests**: `ProfileListsTests` (port of `lists.test.ts` and the draft meta), `InsightsTests` (`ballotOutcome`).
Left for later: the owner ••• menu on Asked rows (edit, end, delete live on the poll screen) and the
header's locks on hidden fields (Stage 5, with Edit profile).
**Status**: Complete

## Stage 4: People and safety
**Goal**: Visitor profile to the design: full-width Follow / Follow back, ••• menu with Share profile,
Copy link and Block with a confirm step. Counts, mutuals, comment reports and share tracking already
landed on main (#21–#23).
**Success Criteria**: Blocking asks first, from every entry point (profile, poll card, comment); the menu
works from a visitor profile.
**Tests**: `MutualFollowersTests` (port of `MutualFollowers.test.tsx`); the smoke test confirms the block.
**Status**: Complete

## Stage 5: Settings parity
**Goal**: The design's grouped Settings and Edit profile; `common.conflict` shown as busy. Notification
switches and passkeys already landed on main (#22, #23).
**Tests**: `conflictSaysBusyInTheShippedStrings` in `I18nTests`; `AccountTests` (the web's visibility and
username tests). Push settings wait for a device-registration API.
**Status**: Complete

## Stage 6: Poll, create, home, explore to the design
**Goal**: Poll action footer and Seal, results summary, Discussion "See all", create sheet (duration chips,
rules card, "Review as a voter"), Home and Explore layouts.
**Status**: Not Started

## Stage 7: Release
**Goal**: Docs current (`release-checklist.md`, `backend-requests.md`), version bump, end-to-end run of the
TestFlight smoke list in the simulator. Hand back what needs a person: Apple team ID, App Store Connect,
`IOS_APP_IDS` on Vercel, push (no device-registration API yet).
**Status**: Not Started
