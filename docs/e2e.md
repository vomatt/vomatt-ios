# End-to-end tests against a local API

`UITests/SignedInFlowTests` signs up with a real one-time code, creates a poll, votes, comments
and signs out, and checks that a session survives an access-token refresh. It needs a vomatt-api
that doesn't send email, so the code can be read from Redis. Without `E2E_OTP_DIR` it skips.

## 1. Run vomatt-api with throwaway databases

Separate containers and ports, so your usual `docker compose` data is left alone:

```bash
cd ../vomatt-api
docker build -f Dockerfile.vercel -t vomatt-api-local .
docker run -d --name vomatt-ios-pg -p 5433:5432 -e POSTGRES_PASSWORD=postgres \
  -v "$PWD/src/main/resources/db/schema.sql:/docker-entrypoint-initdb.d/01-schema.sql:ro" postgres:17
docker run -d --name vomatt-ios-redis -p 6380:6379 redis:7
docker run -d --name vomatt-api-local -p 8080:8080 -e PORT=8080 \
  -e DB_URL=jdbc:postgresql://host.docker.internal:5433/postgres -e DB_USER=postgres -e DB_PASSWORD=postgres \
  -e REDIS_HOST=host.docker.internal -e REDIS_PORT=6380 \
  -e JWT_SECRET=local-ios-dev-secret-0123456789abcdef0123456789 \
  -e JWT_EXPIRATION_SECONDS=120 -e EMAIL_ENABLED=false vomatt-api-local
```

`JWT_EXPIRATION_SECONDS=120` makes the refresh test meaningful (the app refreshes 60s before expiry).

## 2. Copy codes out of Redis

```bash
mkdir -p /tmp/vomatt-otp
while true; do
  for key in $(docker exec vomatt-ios-redis redis-cli --scan --pattern 'otp:email:*'); do
    docker exec vomatt-ios-redis redis-cli GET "$key" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["code"], end="")' > "/tmp/vomatt-otp/${key#otp:email:}.txt"
  done
  sleep 0.5
done
```

## 3. Point a Debug build at it and run

```bash
echo 'VOMATT_API_URL = http:$(SLASH)$(SLASH)localhost:8080' > Configs/Local.xcconfig
TEST_RUNNER_E2E_OTP_DIR=/tmp/vomatt-otp make test-ui
```

Remove `Configs/Local.xcconfig` afterwards to go back to the configured API. Clean up with
`docker rm -f vomatt-api-local vomatt-ios-pg vomatt-ios-redis`.

The UI tests pass `-reset-session` (Debug builds only) so each one starts signed out.
