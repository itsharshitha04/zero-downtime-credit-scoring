#!/usr/bin/env bash
# Continuous traffic test. Run in one PowerShell/WSL/Git Bash terminal while deploying in another.
set -u
BASE_URL="${BASE_URL:-http://localhost:8080}"
DURATION="${DURATION:-90}"
INTERVAL="${INTERVAL:-0.1}"
LOG_FILE="${LOG_FILE:-traffic.log}"
total=0; ok=0; failed=0
start="$(date +%s)"
echo "timestamp,request,status,version,latency_ms" > "$LOG_FILE"
echo "Sending requests to $BASE_URL for ${DURATION}s. Log: $LOG_FILE"
while (( $(date +%s) - start < DURATION )); do
  total=$((total + 1))
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  tmp="$(mktemp)"
  t0="$(date +%s%3N 2>/dev/null || date +%s)"
  code="$(curl -sS --max-time 5 -o "$tmp" -w '%{http_code}' "$BASE_URL/version" 2>/dev/null || echo 000)"
  t1="$(date +%s%3N 2>/dev/null || date +%s)"
  body="$(cat "$tmp" 2>/dev/null || true)"
  rm -f "$tmp"
  version="$(printf '%s' "$body" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')"
  if [[ "$code" == "200" ]]; then
    ok=$((ok + 1))
  else
    failed=$((failed + 1))
  fi
  # On shells without millisecond date support, latency is approximate in seconds.
  latency=$((t1 - t0))
  echo "$ts,$total,$code,${version:-unknown},$latency" >> "$LOG_FILE"
  printf '\rRequests: %d | Success: %d | Failed: %d | Last: %s %s' "$total" "$ok" "$failed" "$code" "${version:-unknown}"
  sleep "$INTERVAL"
done
echo
echo "SUMMARY total=$total successful=$ok failed=$failed"
if (( failed > 0 )); then
  echo "FAIL: requests failed. Inspect $LOG_FILE and Docker/NGINX logs."
  exit 1
fi
echo "PASS: zero failed requests observed during this traffic test."
