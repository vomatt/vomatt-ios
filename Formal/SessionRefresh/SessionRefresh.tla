---------------------------- MODULE SessionRefresh ----------------------------
(* A model of the Session actor in                                            *)
(*   Packages/VomattKit/Sources/VomattCore/Networking/Session.swift           *)
(* and of its callers, AuthMiddleware in Networking/Middleware.swift, plus    *)
(* the refresh endpoint's rule: a refresh token is consumed on first use, and *)
(* one that comes back a second time ends the sign-in.                       *)
(*                                                                            *)
(* One action = one uninterrupted run on the actor (the code between two     *)
(* `await`s), so every interleaving TLC explores is one Swift can produce.    *)
(* Each action names the Swift it mirrors. Read                               *)
(* .claude/skills/verify-session-refresh/SKILL.md before changing anything.   *)

EXTENDS Naturals, FiniteSets, TLC

CONSTANTS
  Callers,    \* concurrent requests going through AuthMiddleware.intercept
  MaxPairs,   \* bound: how many token pairs the backend may ever issue
  MaxTasks,   \* bound: how many refresh requests may be in flight at once
  NULL,
  Variant     \* "code" is Session.swift; the others are deliberately broken copies
              \* used to show that each property can fail (see SKILL.md)

ASSUME Variant \in {"code", "no-join", "save-later", "retry-forever", "clear-by-token", "resurrect"}

Pairs   == 1..MaxPairs   \* an AuthTokens pair; access and refresh token rotate together
TaskIds == 1..MaxTasks   \* slots for the Task { await refresher(token) } calls
Perms   == Permutations(Callers)

VARIABLES
  tokens,     \* Session.tokens                  NULL or a pair
  store,      \* what TokenStore holds           NULL or a pair
  inFlight,   \* Session.inFlight                NULL or [token |-> pair, task |-> TaskId]
  signedOut,  \* TRUE from Session.signOut() until the next Session.signIn()
  tasks,      \* refresh requests: TaskId -> [token, result, issued]; a slot is freed when its last waiter resumed
  nextPair,   \* mints fresh pairs
  valid,      \* backend: refresh tokens it will still accept
  used,       \* backend: refresh tokens it has consumed
  pc,         \* per caller: "idle" | "holding" | "awaiting" | "saving" | "retrying"
  cur,        \* per caller: `current`, the pair captured when refresh() was entered
  failed,     \* per caller: `failedToken` (NULL from accessToken(), the pair from accessTokenAfterRejection)
  myTask,     \* per caller: the task it awaits
  held        \* per caller: the pair whose access token it holds after a return

vars        == <<tokens, store, inFlight, signedOut, tasks, nextPair, valid, used, pc, cur, failed, myTask, held>>
sessionVars == <<tokens, store, inFlight, signedOut>>
backendVars == <<tasks, nextPair, valid, used>>
callerVars  == <<pc, cur, failed, myTask, held>>

FreeSlot == [token |-> NULL, result |-> "none", issued |-> NULL]
Pending  == {t \in TaskIds : tasks[t].result = "pending"}

Init ==
  /\ tokens = 1 /\ store = 1 /\ inFlight = NULL /\ signedOut = FALSE
  /\ tasks = [t \in TaskIds |-> FreeSlot]
  /\ nextPair = 2
  /\ valid = {1} /\ used = {}
  /\ pc = [c \in Callers |-> "idle"]
  /\ cur = [c \in Callers |-> NULL] /\ failed = [c \in Callers |-> NULL]
  /\ myTask = [c \in Callers |-> NULL] /\ held = [c \in Callers |-> NULL]

-----------------------------------------------------------------------------
(* Session.refresh(_:failedToken:) up to `await task.value`: join the         *)
(* in-flight refresh for this refresh token, or start one.                    *)
StartRefresh(c, current, failedToken) ==
  /\ cur' = [cur EXCEPT ![c] = current]
  /\ failed' = [failed EXCEPT ![c] = failedToken]
  /\ pc' = [pc EXCEPT ![c] = "awaiting"]
  /\ IF Variant # "no-join" /\ inFlight # NULL /\ inFlight.token = current
       THEN /\ myTask' = [myTask EXCEPT ![c] = inFlight.task]
            /\ UNCHANGED <<tasks, inFlight>>
       ELSE /\ \E t \in TaskIds : tasks[t].result = "none"
            /\ LET t == CHOOSE t \in TaskIds : tasks[t].result = "none" IN
               /\ tasks' = [tasks EXCEPT ![t] = [token |-> current, result |-> "pending", issued |-> NULL]]
               /\ inFlight' = [token |-> current, task |-> t]
               /\ myTask' = [myTask EXCEPT ![c] = t]
  /\ UNCHANGED <<tokens, store, signedOut, nextPair, valid, used, held>>

(* AuthMiddleware.intercept -> session.accessToken(): the access token is not  *)
(* about to expire, so it is used as is.                                      *)
UseCurrent(c) ==
  /\ pc[c] = "idle" /\ tokens # NULL
  /\ held' = [held EXCEPT ![c] = tokens]
  /\ pc' = [pc EXCEPT ![c] = "holding"]
  /\ UNCHANGED <<sessionVars, backendVars, cur, failed, myTask>>

(* session.accessToken(): the access token is about to expire -> refresh(current) *)
RefreshExpiring(c) ==
  /\ pc[c] = "idle" /\ tokens # NULL
  /\ StartRefresh(c, tokens, NULL)

(* The request came back 401 -> session.accessTokenAfterRejection(of: held)  *)
Rejected401(c) ==
  /\ pc[c] = "holding"
  /\ \/ /\ tokens = NULL                      \* guard let current = tokens else { return nil }
        /\ pc' = [pc EXCEPT ![c] = "idle"]
        /\ held' = [held EXCEPT ![c] = NULL]
        /\ UNCHANGED <<sessionVars, backendVars, cur, failed, myTask>>
     \/ /\ tokens # NULL /\ tokens # held[c]  \* another request already refreshed: retry with its token
        /\ held' = [held EXCEPT ![c] = tokens]
        /\ UNCHANGED <<sessionVars, backendVars, pc, cur, failed, myTask>>
     \/ /\ tokens # NULL /\ tokens = held[c]
        /\ StartRefresh(c, tokens, held[c])

(* Session.refresh after `await task.value`: clear inFlight, apply the result. *)
Resume(c) ==
  /\ pc[c] = "awaiting"
  /\ tasks[myTask[c]].result # "pending"
  /\ LET t == tasks[myTask[c]]
         \* if inFlight?.task == task { inFlight = nil }  ("clear-by-token" is the old test on the token)
         cleared == IF inFlight # NULL /\ (IF Variant = "clear-by-token" THEN inFlight.token = cur[c]
                                                                        ELSE inFlight.task = myTask[c])
                      THEN NULL ELSE inFlight
         \* the Task is released once nobody else awaits it (bookkeeping, not code)
         lastWaiter == \A d \in Callers \ {c} : ~(pc[d] = "awaiting" /\ myTask[d] = myTask[c])
     IN
     /\ tasks' = IF lastWaiter THEN [tasks EXCEPT ![myTask[c]] = FreeSlot] ELSE tasks
     /\ myTask' = [myTask EXCEPT ![c] = NULL]
     /\ IF tokens = NULL /\ Variant # "resurrect" THEN
          \* guard let tokens else { return nil }: signed out while refreshing ("resurrect" lacks it)
          /\ inFlight' = cleared
          /\ held' = [held EXCEPT ![c] = NULL]
          /\ pc' = [pc EXCEPT ![c] = "idle"]
          /\ cur' = [cur EXCEPT ![c] = NULL] /\ failed' = [failed EXCEPT ![c] = NULL]
          /\ UNCHANGED <<tokens, store, signedOut>>
        ELSE IF tokens # NULL /\ tokens # cur[c] THEN
          \* Another caller may already have applied this result
          /\ inFlight' = cleared
          /\ held' = [held EXCEPT ![c] = tokens]
          /\ pc' = [pc EXCEPT ![c] = "holding"]
          /\ cur' = [cur EXCEPT ![c] = NULL] /\ failed' = [failed EXCEPT ![c] = NULL]
          /\ UNCHANGED <<tokens, store, signedOut>>
        ELSE IF t.result = "ok" THEN
          \* tokens = rotated; store.save(rotated); return rotated.accessToken
          /\ inFlight' = cleared
          /\ tokens' = t.issued
          /\ held' = [held EXCEPT ![c] = t.issued]
          /\ IF Variant = "save-later"
               THEN store' = store /\ pc' = [pc EXCEPT ![c] = "saving"]
               ELSE store' = t.issued /\ pc' = [pc EXCEPT ![c] = "holding"]
          /\ cur' = [cur EXCEPT ![c] = NULL] /\ failed' = [failed EXCEPT ![c] = NULL]
          /\ UNCHANGED signedOut
        ELSE IF t.result = "rejected" THEN
          \* signOut(expired: true); return nil
          /\ IF tokens # NULL
               THEN /\ tokens' = NULL /\ store' = NULL /\ inFlight' = NULL /\ signedOut' = TRUE
               ELSE /\ inFlight' = cleared /\ UNCHANGED <<tokens, store, signedOut>>
          /\ held' = [held EXCEPT ![c] = NULL]
          /\ pc' = [pc EXCEPT ![c] = "idle"]
          /\ cur' = [cur EXCEPT ![c] = NULL] /\ failed' = [failed EXCEPT ![c] = NULL]
        ELSE \* "unavailable": keep the session; return failedToken == nil ? current.accessToken : nil
          /\ inFlight' = cleared
          /\ IF Variant = "retry-forever"
               THEN /\ held' = held /\ pc' = [pc EXCEPT ![c] = "retrying"]
                    /\ UNCHANGED <<cur, failed>>
             ELSE /\ IF failed[c] = NULL
                       THEN held' = [held EXCEPT ![c] = cur[c]] /\ pc' = [pc EXCEPT ![c] = "holding"]
                       ELSE held' = [held EXCEPT ![c] = NULL]   /\ pc' = [pc EXCEPT ![c] = "idle"]
                  /\ cur' = [cur EXCEPT ![c] = NULL] /\ failed' = [failed EXCEPT ![c] = NULL]
          /\ UNCHANGED <<tokens, store, signedOut>>
  /\ UNCHANGED <<nextPair, valid, used>>

(* Only in Variant "retry-forever": an unavailable refresh is retried instead   *)
(* of returned, as a well-meant "fix" might do.                               *)
Retry(c) ==
  /\ pc[c] = "retrying"
  /\ \/ /\ tokens = NULL
        /\ pc' = [pc EXCEPT ![c] = "idle"] /\ held' = [held EXCEPT ![c] = NULL]
        /\ cur' = [cur EXCEPT ![c] = NULL] /\ failed' = [failed EXCEPT ![c] = NULL]
        /\ UNCHANGED <<sessionVars, backendVars, myTask>>
     \/ /\ tokens # NULL
        /\ StartRefresh(c, tokens, failed[c])

(* Only in Variant "save-later": the store write happens after a suspension.  *)
SaveLater(c) ==
  /\ pc[c] = "saving"
  /\ store' = held[c]
  /\ pc' = [pc EXCEPT ![c] = "holding"]
  /\ UNCHANGED <<tokens, inFlight, signedOut, backendVars, cur, failed, myTask, held>>

-----------------------------------------------------------------------------
(* POST /api/auth/refresh. A valid refresh token is consumed and a new pair   *)
(* issued; anything else is refused (a consumed one with `suspicious`).       *)
BackendAnswers(t) ==
  /\ tasks[t].result = "pending"
  /\ IF tasks[t].token \in valid
       THEN /\ nextPair <= MaxPairs
            /\ valid' = (valid \ {tasks[t].token}) \cup {nextPair}
            /\ used' = used \cup {tasks[t].token}
            /\ tasks' = [tasks EXCEPT ![t].result = "ok", ![t].issued = nextPair]
            /\ nextPair' = nextPair + 1
       ELSE /\ tasks' = [tasks EXCEPT ![t].result = "rejected"]
            /\ UNCHANGED <<valid, used, nextPair>>
  /\ UNCHANGED <<sessionVars, callerVars>>

(* VomattService.refresh returned .unavailable: offline, 5xx or rate limited.  *)
(* Assumed here: the backend did not consume the token.                       *)
NetworkFails(t) ==
  /\ tasks[t].result = "pending"
  /\ tasks' = [tasks EXCEPT ![t].result = "unavailable"]
  /\ UNCHANGED <<sessionVars, nextPair, valid, used, callerVars>>

-----------------------------------------------------------------------------
(* VomattService.signOut / deleteAccount -> Session.signOut()                 *)
SignOut ==
  /\ tokens # NULL
  /\ tokens' = NULL /\ store' = NULL /\ inFlight' = NULL /\ signedOut' = TRUE
  /\ UNCHANGED <<backendVars, callerVars>>

(* verifyOtp and the social logins -> Session.signIn(pair the backend issued). *)
(* Modelled only while signed out, which is the only time the app offers it.   *)
SignIn ==
  /\ tokens = NULL
  /\ nextPair <= MaxPairs
  /\ tokens' = nextPair /\ store' = nextPair /\ signedOut' = FALSE
  /\ valid' = valid \cup {nextPair}
  /\ nextPair' = nextPair + 1
  /\ UNCHANGED <<inFlight, tasks, used, callerVars>>

-----------------------------------------------------------------------------
Next ==
  \/ \E c \in Callers : UseCurrent(c) \/ RefreshExpiring(c) \/ Rejected401(c) \/ Resume(c)
                        \/ SaveLater(c) \/ Retry(c)
  \/ \E t \in TaskIds : BackendAnswers(t) \/ NetworkFails(t)
  \/ SignOut \/ SignIn

\* Refresh requests complete and resumed callers get the actor back.
Fairness ==
  /\ \A c \in Callers : WF_vars(Resume(c)) /\ WF_vars(SaveLater(c)) /\ WF_vars(Retry(c))
  /\ \A t \in TaskIds : WF_vars(BackendAnswers(t) \/ NetworkFails(t))

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* Properties. Each is one sentence in SKILL.md.                             *)

TypeOK ==
  /\ tokens \in Pairs \cup {NULL} /\ store \in Pairs \cup {NULL}
  /\ inFlight = NULL \/ inFlight \in [token : Pairs, task : TaskIds]
  /\ \A t \in TaskIds : tasks[t].result \in {"none", "pending", "ok", "rejected", "unavailable"}
  /\ \A c \in Callers : pc[c] \in {"idle", "holding", "awaiting", "saving", "retrying"}
  \* model bookkeeping: a slot is never freed under someone's feet
  /\ \A c \in Callers : pc[c] = "awaiting" => tasks[myTask[c]].result # "none"
  /\ inFlight # NULL => tasks[inFlight.task].token = inFlight.token

\* No refresh request carries a token the backend has already consumed, and no two
\* requests carry the same token (the backend would consume it once and end the
\* sign-in when it came back again).
NeverSendsAUsedRefreshToken ==
  /\ \A t \in Pending : tasks[t].token \notin used
  /\ \A t1, t2 \in Pending : t1 # t2 => tasks[t1].token # tasks[t2].token

\* What the Keychain holds is what the session uses: a rotated pair is saved before anyone uses it.
StoreMatchesSession == store = tokens

\* A sign-out is final until the next sign-in: nothing is kept or saved in between.
SignOutSticks == signedOut => tokens = NULL /\ store = NULL

\* No caller waits on a refresh forever.
EveryCallerReturns == \A c \in Callers : pc[c] \in {"awaiting", "retrying"} ~> pc[c] \in {"idle", "holding"}

=============================================================================
