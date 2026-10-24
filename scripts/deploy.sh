```bash
#!/usr/bin/env bash
# Zero-downtime Blue-Green deployment for the simulated credit scoring API.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

GREEN_VERSION="${1:-green-v2}"
READY_TIMEOUT="${READY_TIMEOUT:-60}"
VERIFY_REQUESTS="${VERIFY_REQUESTS:-20}"
BASE_URL="${BASE_URL:-http://localhost:8081}"
ACTIVE_FILE=".active_color"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

command -v docker >/dev/null 2>&1 ||
  fail "Docker CLI not found. Start Docker Desktop first."

# Check Docker Compose without incorrectly treating the installed version
# as a failure. Docker Compose v2 uses the 'docker compose' command.
if ! docker compose version; then
  fail "Docker Compose is unavailable. Check Docker Desktop."
fi

# Ensure BLUE and NGINX are running.
docker compose up -d blue nginx

# Initialize active color if needed.
if [[ ! -f "$ACTIVE_FILE" ]]; then
  printf 'blue\n' > "$ACTIVE_FILE"
fi

CURRENT="$(tr -d '\r\n' < "$ACTIVE_FILE")"

if [[ "$CURRENT" != "blue" && "$CURRENT" != "green" ]]; then
  fail "Invalid active color in $ACTIVE_FILE: $CURRENT"
fi

if [[ "$CURRENT" != "blue" ]]; then
  fail "BLUE is not marked active. Run scripts/rollback.sh before another deployment."
fi

log "Building and starting GREEN ($GREEN_VERSION)..."
GREEN_VERSION="$GREEN_VERSION" docker compose --profile green up -d --build green

log "Waiting for GREEN readiness (timeout ${READY_TIMEOUT}s)..."
deadline=$((SECONDS + READY_TIMEOUT))
ready=0

while (( SECONDS < deadline )); do
  status="$(docker inspect --format '{{.State.Health.Status}}' credit-green 2>/dev/null || true)"

  if [[ "$status" == "healthy" ]]; then
    ready=1
    break
  fi

  sleep 2
done

if (( ready == 0 )); then
  log "GREEN failed readiness. BLUE remains active."
  docker compose --profile green stop -t 10 green || true
  fail "Deployment aborted. Check GREEN logs with: docker logs credit-green"
fi

log "GREEN passed its container readiness check."

# Save the current configuration so it can be restored if validation fails.
cp nginx/active/upstream.conf nginx/upstream.previous.conf

# Atomically replace the active NGINX configuration.
cp nginx/upstream.green.conf nginx/active/upstream.conf.tmp
mv nginx/active/upstream.conf.tmp nginx/active/upstream.conf

log "Validating NGINX configuration..."
if ! docker exec credit-nginx nginx -t; then
  cp nginx/upstream.previous.conf nginx/active/upstream.conf
  docker exec credit-nginx nginx -t || true
  fail "NGINX config validation failed. Previous config restored."
fi

log "Gracefully reloading NGINX..."
if ! docker exec credit-nginx nginx -s reload; then
  cp nginx/upstream.previous.conf nginx/active/upstream.conf
  docker exec credit-nginx nginx -t &&
    docker exec credit-nginx nginx -s reload || true
  fail "NGINX reload failed. Previous config restored."
fi

log "Verifying that GREEN serves ${VERIFY_REQUESTS} requests..."

for ((i = 1; i <= VERIFY_REQUESTS; i++)); do
  body="$(curl --silent --show-error --fail --max-time 5 \
    "$BASE_URL/version")" || {
      log "Request $i failed. Attempting rollback."
      bash scripts/rollback.sh || true
      fail "Post-switch verification failed."
    }

  if ! grep -Fq "\"version\":\"$GREEN_VERSION\"" <<< "$body"; then
    log "Unexpected response: $body"
    log "Attempting rollback."
    bash scripts/rollback.sh || true
    fail "GREEN version verification failed."
  fi
done

printf 'green\n' > "$ACTIVE_FILE"

log "GREEN is active: $GREEN_VERSION"
log "Stopping BLUE gracefully after successful verification..."
docker compose stop -t 35 blue

log "Deployment complete."
log "BLUE is stopped but retained for rollback."
```