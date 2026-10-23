# v2 design, iOS first

Source of truth for the look: the "Vomatt v2 Design" canvas (claude.ai artifact CxcjFtJs913wLaf9JkFUSn).
Colors still flow from `../vomatt-web/src/styles/global.css` through `scripts/sync.sh tokens`.

## Stage 1: Tokens
**Goal**: Navy ink, brand Volt, Tide (the promise color) and navy-cast Night in `global.css`, synced to the asset catalog and `Tokens.generated.swift`.
**Success Criteria**: `scripts/sync.sh tokens` runs clean; `Tokens.tide*` exist; the app builds.
**Tests**: `make build`.
**Status**: Complete

## Stage 2: Type and shape
**Goal**: Titles at weight 500; cards 16pt, rows and inputs 12pt, buttons 10pt, pills full.
**Success Criteria**: `Radius.card` used by `.card()`; `FieldChrome` and ballot rows at `Radius.xl`; buttons at `Radius.lg` = 10.
**Tests**: `make build`.
**Status**: Complete

## Stage 3: The Seal
**Goal**: After a ballot is cast, the card shows the Seal (Tide surface, Tide ring, Volt check) with "Sealed. Thank you.", the reveal date and turnout, instead of the "Vote cast." toast. Later views show the compact seal row.
**Success Criteria**: Casting shows the expanded Seal once; reopening the poll shows the compact row; VoiceOver announces the seal.
**Tests**: `make build`; observed in the simulator.
**Status**: Built and reviewed; not yet observed at runtime (voting needs a signed-in session: see `.claude/skills/verify`)

## Stage 4: Night follows the system
**Goal**: Confirm nothing forces light mode and the Night tokens render.
**Success Criteria**: Simulator in dark appearance shows the navy canvas.
**Tests**: observed in the simulator.
**Status**: Complete (Info.plist sets no UIUserInterfaceStyle; dark screenshots show the navy canvas)
