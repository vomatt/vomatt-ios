# Backend requests from the iOS app

What vomatt-api needs before the remaining App Store items can ship. Content reports and blocking,
asked for here earlier, have landed (`POST /api/votes/{voteId}/report`, `…/comments/{commentId}/report`,
`/api/users/me/blocks`). Each follows the API's
conventions: the `{ success, data, message, errorCode }` envelope, lowercase dotted error codes,
Bearer auth. Once one lands in `api-docs.json`, `scripts/sync.sh api` shows it and the app can use it.

## 1. Push notification devices

Invitations and Ended Notifications already exist; the app shows them only as the unread dot.

| Endpoint | Body | Notes |
|---|---|---|
| `POST /api/devices` | `{ "token": "<APNs hex>", "platform": "ios", "environment": "sandbox" \| "production", "language": "en" \| "zh-TW" }` | Upsert by token; one user can have many devices. 201 |
| `DELETE /api/devices/{token}` | | On sign-out and account deletion. Idempotent |

Send an APNs alert when a user gets an Invitation or an Ended Notification, with
`{ "voteId": "<id>", "kind": "invitation" \| "ended" }` in the payload so the app opens the poll
(`vomatt://poll/<id>`). Revoke the user's devices on `POST /api/auth/logout` and when every session is
revoked. Needs an APNs key (`.p8`) from the Apple Developer account.

## 2. Sign in with Apple for the app

`POST /api/auth/apple` exists. For the app's identity tokens, `APPLE_CLIENT_ID` must accept the
bundle ID `com.vomatt.app` as an audience (alongside any web Service ID). The app sends `idToken` and,
on first sign-in only, `fullName`. App Store guideline 4.8 doesn't require it while email is the only
sign-in, but it is required as soon as Google or LINE sign-in ships in the app.
