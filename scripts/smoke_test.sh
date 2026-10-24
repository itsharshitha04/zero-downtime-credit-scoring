#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"
echo "Health:"
curl -fsS "$BASE_URL/healthz"; echo
echo "Readiness:"
curl -fsS "$BASE_URL/readyz"; echo
echo "Version:"
curl -fsS "$BASE_URL/version"; echo
echo "Prediction:"
curl -fsS -X POST "$BASE_URL/predict" -H 'Content-Type: application/json' \
  -d '{"annual_income":65000,"existing_debt":12000,"payment_history_score":0.9}'
echo
