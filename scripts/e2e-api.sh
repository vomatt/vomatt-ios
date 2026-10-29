#!/usr/bin/env bash
# A throwaway vomatt-api for the E2E tests and runtime checks (docs/e2e.md): its own Postgres and
# Redis on a private network, email off, and a known APP_KEY so scripts/e2e-otp.py can read codes.
#
#   scripts/e2e-api.sh up      build vomatt-api (API_DIR, default ../vomatt-api) and start it on :8080
#   scripts/e2e-api.sh down    remove the containers and the network
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API_DIR="${API_DIR:-$ROOT/../vomatt-api}"
NET=vomatt-ios-net
# Local only; e2e-otp.py derives the OTP key from the same value
APP_KEY=local-ios-dev-app-key-0123456789abcdef0123456789

down() {
	docker rm -f vomatt-api-local vomatt-ios-pg vomatt-ios-redis >/dev/null 2>&1 || true
	docker network rm "$NET" >/dev/null 2>&1 || true
}

up() {
	down
	docker build -q -f "$API_DIR/Dockerfile.vercel" -t vomatt-api-local "$API_DIR" >/dev/null
	docker network create "$NET" >/dev/null
	docker run -d --name vomatt-ios-pg --network "$NET" -e POSTGRES_PASSWORD=postgres postgres:17 >/dev/null
	docker run -d --name vomatt-ios-redis --network "$NET" -p 6380:6379 redis:7 >/dev/null
	until docker exec vomatt-ios-pg pg_isready -U postgres -h localhost >/dev/null 2>&1; do sleep 1; done
	# Flyway creates the schema at startup. JWT_EXPIRATION_SECONDS=120 makes the refresh test meaningful
	docker run -d --name vomatt-api-local --network "$NET" -p 8080:8080 -e PORT=8080 \
		-e DB_URL=jdbc:postgresql://vomatt-ios-pg:5432/postgres -e DB_SSLMODE=disable -e DB_USER=postgres -e DB_PASSWORD=postgres \
		-e REDIS_HOST=vomatt-ios-redis -e REDIS_PORT=6379 \
		-e JWT_SECRET=local-ios-dev-secret-0123456789abcdef0123456789 -e APP_KEY="$APP_KEY" \
		-e JWT_EXPIRATION_SECONDS=120 -e EMAIL_ENABLED=false vomatt-api-local >/dev/null
	for _ in $(seq 60); do
		if docker logs vomatt-api-local 2>&1 | grep -q "Started VomattApiApplication"; then
			echo "vomatt-api $(git -C "$API_DIR" rev-parse --short HEAD) on http://localhost:8080"
			return
		fi
		sleep 1
	done
	docker logs vomatt-api-local 2>&1 | grep "Caused by" | tail -3
	echo "e2e-api.sh: the API did not start" >&2
	exit 1
}

case "${1:-}" in
	up) up ;;
	down) down ;;
	*) sed -n '2,7p' "$0"; exit 1 ;;
esac
