# Keeping the app in step with vomatt-api

The contract is `Packages/VomattKit/Sources/VomattAPI/openapi.json`, a copy of the same document
vomatt-web keeps as `api-docs.json` (what vomatt-api serves at `/v3/api-docs`). The Swift client and
types are generated from it on every build, so the app can only call what the contract describes.

## Updating

1. Pull the new contract and read what changed:

   ```bash
   scripts/sync.sh api                                     # from ../vomatt-web/api-docs.json
   scripts/sync.sh api --url https://vomatt-api.vercel.app # or straight from a deployed API
   ```

   The script prints a summary before writing the file, for example:

   ```
   + operation  POST /api/votes/{voteId}/report  (reportVote)
   ~ operation  GET /api/votes  params changed +['query:creatorUsername'] -[]
   + property   VoteResponse.reportCount  ('integer', 'int64', False, ())
   ~ required   CreateVoteRequest  ['endTime', 'options', 'title'] -> ['endTime', 'options', 'title', 'audience']
   ```

   The file is written with sorted keys, so the git diff is readable too.

2. `make test-core`. The build regenerates the client:
   - A renamed or removed field or operation fails to compile in `Networking/Mapping.swift` or
     `VomattService.swift`. Those two files are the only places that touch generated types.
   - A new field compiles silently; add it to the model in `VomattCore/Models` and the mapping if the
     app should use it.
   - Generated initializers take their arguments in alphabetical order (the sorted keys).

3. Add a test in `ServiceTests.swift` for any new behavior (a stub transport answers with fixture
   JSON; capture a real payload into `Tests/VomattCoreTests/Fixtures` when you can).

4. Build the app, then commit `openapi.json` with the code that uses it.

## Checking for drift

- `make sync-check` fails when the contract, strings or avatars differ from `../vomatt-web`.
- `make api-diff API_URL=https://…` compares the contract with what a deployed API serves.

## Where things live

| Concern | File |
|---|---|
| Which operations are generated | `openapi-generator-config.yaml` (`filter.tags`; the admin tags are left out) |
| Envelope and errors | `Networking/Middleware.swift`: non-2xx answers become `APIError` with the API's `errorCode`, `message` and `Retry-After` |
| Tokens and refresh | `Networking/Session.swift`, `AuthMiddleware` |
| Dates | `Networking/LenientDateTranscoder.swift` (the API mixes fractional and whole seconds) |
| Generated → domain | `Networking/Mapping.swift` |
| Calls | `VomattService.swift` |

## The other shared pieces

| Piece | Source in vomatt-web | Command |
|---|---|---|
| Strings | `src/locales/{en,zh}.json` | `scripts/sync.sh locales` |
| Color tokens | `src/styles/global.css` (OKLCh → Display P3 colorsets + `Tokens.generated.swift`) | `scripts/sync.sh tokens` |
| Bot avatars | `public/avatars/*.svg` | `scripts/sync.sh avatars` |

iOS-only strings go in `App/Resources/Locales/ios.{en,zh}.json`, which override the shared files;
never edit the copied `en.json`/`zh.json` here, change them in vomatt-web and sync.
