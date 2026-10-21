---
name: verify-session-refresh
description: Model-check the Session actor's token refresh with TLA+/TLC. Use after any change to Packages/VomattKit/Sources/VomattCore/Networking/Session.swift, AuthMiddleware in Networking/Middleware.swift, or VomattService.refresh/signOut/signIn, and before relying on "refreshes are single-flight". Proves, over every interleaving of concurrent requests, that no consumed refresh token is ever sent again and that a sign-out sticks.
---

# Verifying the Session refresh with TLC

The backend rotates the refresh token on every refresh and ends the sign-in when a used one comes
back. `Session` promises that concurrent requests share one refresh, that a rotated pair is saved
before anyone uses it, and that a sign-out is final. Tests cover a handful of orderings; this check
covers every ordering of actor hops, bounded as below. Run it in ~10 s: `make formal`.

## The properties (Formal/SessionRefresh/SessionRefresh.tla)

| Property | Plain words | Harm when it breaks |
| --- | --- | --- |
| `NeverSendsAUsedRefreshToken` | No refresh request carries a token the backend already consumed, and no two requests carry the same token. | The backend sees a used token and ends the sign-in: the user is thrown out with "session expired". |
| `StoreMatchesSession` | The Keychain always holds exactly the pair the session uses. | A kill between rotate and save loses the session, or keeps a dead one. |
| `SignOutSticks` | From `signOut()` until the next `signIn()`, nothing is kept in memory or saved. | A signed-out device still holds a live session; the next launch is signed in. |
| `EveryCallerReturns` | No caller waits on a refresh forever. | Requests hang. |
| `TypeOK` | Model bookkeeping only (shapes, slot reuse). | A failure here is a model bug, never a code bug. |

## Run it

```bash
make formal                                      # all properties, model of the current code
VARIANT=no-join Formal/check-session.sh          # a deliberately broken copy (see "Able to fail")
Formal/check-session.sh SignOutSticks            # one property
```

Needs `brew install openjdk`; the TLA+ tools jar (v1.7.4, pinned by checksum) is fetched once into
`Formal/.tools/`. Output is a verdict table; on FAIL it prints the step sequence and the full trace
is in `Formal/out/<variant>/<property>.log`. Exit 0 means every property passed, 1 means a
counterexample, 2 means TLC did not run (read the log).

## Expected output at the sync commit

Every property PASS, exit 0. A FAIL is a finding, not a model error: do not weaken the property;
fix the code, or record it here as a known finding. TLC reports one shortest trace; its exact steps
can differ a little between runs.

## Findings this model has made

Both were in the code when the model was first written and are fixed in 32ee931. The
Swift tests `aStaleWaiterDoesNotClearANewerRefresh` and `aRefreshFinishingAfterSignOutIsDropped`
in `Packages/VomattKit/Tests/VomattCoreTests/ServiceTests.swift` pin them; the variants
`clear-by-token` and `resurrect` reproduce them in the model.

**F1, duplicate refresh after an unavailable one** (`Session.refresh`, the line
`if inFlight?.refreshToken == current.refreshToken { inFlight = nil }`). Request A starts a refresh
with token R1; request B joins it. The network fails, so the result is `.unavailable` and R1 stays
unused. A resumes first, clears `inFlight`, and returns. A's next request starts a *new* refresh
with R1 (`inFlight` now records that task). B resumes late: its `current` is still R1, so it clears
`inFlight` even though that record belongs to the newer task. B's retry then finds no in-flight
refresh and starts a third one with R1. Two requests now carry R1; whichever the backend sees second
comes back `rejected(suspicious: true)` and the sign-in ends. Needs: a flaky network (the
`.unavailable`) and one actor job landing between two waiters' resumptions, then any request while
the second refresh is in flight. Fix: the clear tests the task (`inFlight?.task == task`), not the
token. Trace: `Initial > RefreshExpiring > UseCurrent > Rejected401 > NetworkFails > Resume >
Rejected401 > Resume > RefreshExpiring`.

**F2, an in-flight refresh undoes a sign-out** (`Session.refresh`, the `.ok` case). A refresh is in
flight when the user signs out: `signOut()` clears `tokens`, `inFlight` and the store. The refresh
then completes `.ok`; `refresh` finds `tokens == nil`, so the "another caller already applied this"
guard does not fire, and it sets and saves the rotated pair. The UI stays signed out (no
`.signedIn` event), but the Keychain holds a live pair and the next launch is signed in. Needs: a
sign-out during the refresh round trip. Fix: `guard let active = tokens else { return nil }` drops
a result that arrives while signed out. Trace: `Initial > UseCurrent > Rejected401 >
RefreshExpiring > BackendAnswers > SignOut > Resume`.

## Reading a failure

- The step line names the model's actions in order. Each action's comment in the `.tla` names the
  Swift it mirrors: `RefreshExpiring` = `accessToken()` with an expiring token, `Rejected401` =
  `accessTokenAfterRejection`, `Resume` = the code after `await task.value`, `BackendAnswers` /
  `NetworkFails` = the refresh endpoint answering / `.unavailable`, `SignOut` / `SignIn` = the
  service calling `Session.signOut` / `signIn`.
- In the log, `tokens`/`store`/`inFlight` are `Session`'s fields, `pc[c]`, `cur[c]`, `failed[c]`,
  `held[c]` are one request's position and locals, `tasks` the refresh requests in flight,
  `valid`/`used` what the backend would accept / has consumed.
- **Real bug**: you can replay the steps against the Swift and each step is one run on the actor
  between two `await`s (or one backend answer, or one user action). Retell it as above and report it.
- **Model error**: a step the code cannot take (a result applied without awaiting, a caller
  skipping a guard), or a `TypeOK` failure. Fix the model, then rerun.

## After an intended change to the covered code

1. Find the action that mirrors the changed Swift (comments in the `.tla`) and change it the same
   way. Keep one action per uninterrupted run on the actor: a new `await` splits an action in two;
   a removed one merges two. New state in `Session` becomes a variable with its `Init`.
2. If the change fixes a finding, add a `Variant` that keeps the old behaviour (see below) so the
   property can still be seen failing, and record the finding above.
3. Run `make formal`, then each variant in "Able to fail" and confirm each still fails.
4. Move the sync commit in "Coverage" forward only after you have confirmed that every action
   still describes the code at that commit.

## Able to fail

Each property has been seen failing, so a PASS means something:

| Property | Fails on | What the variant breaks |
| --- | --- | --- |
| `NeverSendsAUsedRefreshToken` | `VARIANT=clear-by-token` (F1); `VARIANT=no-join` | `inFlight` cleared by refresh token, not task; every caller starts its own refresh |
| `StoreMatchesSession` | `VARIANT=save-later` | `store.save` after a suspension |
| `SignOutSticks` | `VARIANT=resurrect` (F2) | a result arriving after sign-out is applied |
| `EveryCallerReturns` | `VARIANT=retry-forever` | an unavailable refresh is retried instead of returned |

Variants live in the `.tla` as `IF Variant = ...` branches, each marked. They are not the code.

## Bounds and assumptions

- 3 concurrent requests (2 for `EveryCallerReturns`), at most 3 refreshes in flight, the backend
  issues at most 4 token pairs, callers loop. ~190k states for the invariants, under 10 s.
- `.unavailable` means the backend did not consume the token. `VomattService.refresh` also maps
  5xx and rate limiting to `.unavailable`; a backend that rotated and then failed to respond would
  make the next refresh `rejected` on any client, and is out of scope.
- `signIn` is modelled only while signed out, which is when the app offers it.
- Logout's revoke on the backend, token expiry times, the Keychain's own failures, and the
  `events` stream are not modelled. `AuthMiddleware`'s unauthenticated operations are not modelled.
- A pass covers the model within these bounds, not the running system.

## Coverage

| Swift | Model |
| --- | --- |
| `Session.refresh(_:failedToken:)` | `StartRefresh`, `Resume` |
| `Session.accessToken(now:)` | `UseCurrent`, `RefreshExpiring` |
| `Session.accessTokenAfterRejection(of:)` | `Rejected401` |
| `Session.signIn`, `Session.signOut` | `SignIn`, `SignOut` |
| `AuthMiddleware.intercept` (Networking/Middleware.swift) | the caller loop: `idle` → `holding` → `Rejected401` |
| `VomattService.refresh` (`.ok`/`.rejected`/`.unavailable`), `signOut`, `deleteAccount`, `verifyOtp` | `BackendAnswers`, `NetworkFails`, `SignOut`, `SignIn` |

Sync commit: **32ee931** (the commit that fixed F1 and F2). `make formal` prints the last
commit that touched the covered files; if it is newer than the sync commit, re-read the Swift
against the model before trusting a PASS.

Related: `/maintain-formal-verification-skill` (pstack) brings this back in line after changes that
skipped step 4.
