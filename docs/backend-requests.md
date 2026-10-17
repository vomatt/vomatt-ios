# Backend requests from the iOS app

What vomatt-api needs before the remaining App Store items can ship. Each follows the API's
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

## 2. Content reports (App Review 1.2)

| Endpoint | Body | Notes |
|---|---|---|
| `POST /api/reports` | `{ "targetType": "vote" \| "comment" \| "user", "targetId": "<id>", "reason": "spam" \| "harassment" \| "hate" \| "other", "details": "<≤1000>" }` | 201. `report.duplicate` when the same user reports the same target again |

Today the app opens an email to `VOMATT_SUPPORT_EMAIL` instead. Apple expects reports to be acted on
within 24 hours, so someone needs to read them either way.

## 3. Blocking users

| Endpoint | Notes |
|---|---|
| `GET /api/users/me/blocks` | Cursor-paged `UserDto` |
| `PUT /api/users/{username}/block` | Idempotent |
| `DELETE /api/users/{username}/block` | Idempotent |

Leave blocked users' Polls and Comments out of lists for the blocker. Today the app keeps the list on
the device (`BlockList` in VomattCore) and filters on the client; it would move its list to the
server on first sign-in once these exist.

## 4. Sign in with Apple for the app

`POST /api/auth/apple` exists. For the app's identity tokens, `APPLE_CLIENT_ID` must accept the
bundle ID `com.vomatt.app` as an audience (alongside any web Service ID). The app sends `idToken` and,
on first sign-in only, `fullName`. App Store guideline 4.8 doesn't require it while email is the only
sign-in, but it is required as soon as Google or LINE sign-in ships in the app.
