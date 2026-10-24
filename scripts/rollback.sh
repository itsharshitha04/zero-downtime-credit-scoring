#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

command -v docker >/dev/null || { echo "Docker CLI not found"; exit 1; }
if ! docker inspect credit-blue >/dev/null 2>&1; then
  log "BLUE container missing; starting it..."
  docker compose up -d --build blue
else
  docker start credit-blue >/dev/null 2>&1 || true
fi

log "Waiting for BLUE readiness..."
deadline=$((SECONDS + 45))
ready=0
while (( SECONDS < deadline )); do
  status="$(docker inspect --format '{{.State.Health.Status}}' credit-blue 2>/dev/null || true)"
  if [[ "$status" == "healthy" ]]; then ready=1; break; fi
  sleep 2
done
if (( ready == 0 )); then
  log "BLUE is not healthy; refusing to switch traffic."
  exit 1
fi

cp nginx/upstream.blue.conf nginx/active/upstream.conf.tmp
mv nginx/active/upstream.conf.tmp nginx/active/upstream.conf
docker exec credit-nginx nginx -t
docker exec credit-nginx nginx -s reload
printf 'blue\n' > .active_color

log "BLUE restored. Verifying route..."
curl --fail --silent --show-error http://localhost:8081/version
echo
log "Rollback complete. GREEN is left running for investigation; stop it manually after review."

