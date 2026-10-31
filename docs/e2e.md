# End-to-end tests against a local API

`UITests/SignedInFlowTests` signs up with a real one-time code, creates a poll, votes, comments
and signs out, and checks that a session survives an access-token refresh. It needs a vomatt-api
that doesn't send email, so the code can be read from Redis. Without `E2E_OTP_DIR` it skips.

## 1. Run vomatt-api with throwaway databases

```bash
scripts/e2e-api.sh up
```

It builds `../vomatt-api` (`API_DIR`), and runs it on :8080 with its own Postgres and Redis on a private
network, so your usual `docker compose` data is left alone. Flyway creates the schema, email is off, and
`JWT_EXPIRATION_SECONDS=120` makes the refresh test meaningful (the app refreshes 60s before expiry).

## 2. Hand codes to the tests

```bash
scripts/e2e-otp.py /tmp/vomatt-otp
```

The API stores only an HMAC of each code. A test asks for one by creating `<email>.want` in the folder,
and the script, which knows the local `APP_KEY`, writes the code to `<email>.txt`.

## 3. Point a Debug build at it and run

```bash
echo 'VOMATT_API_URL = http:$(SLASH)$(SLASH)localhost:8080' > Configs/Local.xcconfig
TEST_RUNNER_E2E_OTP_DIR=/tmp/vomatt-otp make test-ui
```

Remove `Configs/Local.xcconfig` afterwards to go back to the configured API. Clean up with
`scripts/e2e-api.sh down`.

The UI tests pass `-reset-session` (Debug builds only) so each one starts signed out.
