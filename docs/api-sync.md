# Keeping the app in step with vomatt-api

The contract is `Packages/VomattKit/Sources/VomattAPI/openapi.json`, a copy of vomatt-api's
`docs/frontend/openapi.json` (what it serves at `/v3/api-docs`). vomatt-web keeps its own copy as
`api-docs.json`, which can lag behind endpoints the web already calls, so the app reads vomatt-api's.
The Swift client and types are generated from it on every build, so the app can only call what the
contract describes.

## Updating

1. Pull the new contract and read what changed:

   ```bash
   scripts/sync.sh api                                     # ../vomatt-api's docs/frontend/openapi.json at origin/main
   scripts/sync.sh api --url https://vomatt-api-production.up.railway.app # or straight from a deployed API
   scripts/sync.sh api --file path/to/openapi.json         # or any file, e.g. another vomatt-api commit's
   ```

   `API_DIR` points at the vomatt-api checkout and `API_REF` at the commit to read (default
   `origin/main`, fetched first), so work in progress in its working tree never reaches the app.

   The script prints a summary before writing the file, for example:

   ```
   + operation  POST /api/votes/{voteId}/report  (reportVote)
   ~ operation  GET /api/votes  params changed +['query:creatorUsername'] -[]
   + property   VoteResponse.reportCount  ('integer', 'int64', False, ())
   ~ required   CreateVoteRequest  ['endTime', 'options', 'title'] -> ['endTime', 'options', 'title', 'audience']
   ```

   The summary covers only what the app calls: operations whose tag is in `filter.tags` of
   `openapi-generator-config.yaml` or whose `operationId` is in its `filter.operations`, and the
   schemas they use. Admin endpoints (`Admin …` tags) belong
   to the admin console, so their changes are left out and only counted on stderr. To bring an API
   area into the app, add its tag to `filter.tags`. `Auth` is listed by operation in
   `filter.operations` instead, to leave out the admin console's sign-in. A changed Auth operation
   that isn't listed is named on a `? operation` line; add its `operationId` there if the app
   needs it.

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

## Automatic sync

When `docs/frontend/openapi.json` changes on vomatt-api's main, its `notify-ios-contract` workflow sends
a `repository_dispatch` (`api-contract-updated`) here, and `.github/workflows/sync-api-contract.yml`
has Claude follow this page and open a PR (none when the app is already in step). Run it by hand
from the Actions tab with an optional vomatt-api `sha`.

Secrets: `CLAUDE_CODE_OAUTH_TOKEN` here, `API_READ_TOKEN` here if vomatt-api is private,
`SYNC_PR_TOKEN` here (a PAT that can open PRs; without it the PR is opened with `github.token` and
ios.yml does not run on it), and
`IOS_DISPATCH_TOKEN` in vomatt-api (a fine-grained PAT with "Contents: read and write" on vomatt-ios).

## Checking for drift

- `make sync-check` fails when the strings or avatars differ from `../vomatt-web`, or the contract from `../vomatt-api`.
- `make api-diff API_URL=https://…` compares the contract with what a deployed API serves.

## Where things live

| Concern | File |
|---|---|
| Which operations are generated | `openapi-generator-config.yaml` (`filter.tags`, plus the Auth operations in `filter.operations`; admin is left out) |
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
