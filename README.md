# Zero-Downtime Blue-Green Credit Risk Scoring Demo

A local demonstration of blue-green deployment for a simulated Flask credit-risk scoring API, Docker Compose, NGINX, and Bash. Intended for learning and deployment testing only. The score is **not a validated credit model and must not be used for real lending decisions**.

## Architecture

- `credit-blue` starts as the active service.
- `credit-green` is started separately and must pass its Docker readiness health check.
- NGINX routes requests using `nginx/active/upstream.conf` (the active config directory is bind-mounted so atomic file replacement is visible inside the container).
- `scripts/deploy.sh` validates and gracefully reloads NGINX to route to GREEN, verifies the version, then stops BLUE with a grace period.
- `scripts/rollback.sh` starts BLUE if needed, waits for readiness, switches NGINX back, and reloads it.
- `scripts/traffic_test.sh` sends requests continuously and records status/version in `traffic.log`.

## Requirements (Windows)

1. Install and start Docker Desktop, using Linux containers.
2. Install Git for Windows (includes Git Bash) or use WSL 2 with Bash.
3. Install `curl` (available in current Windows versions; Git Bash/WSL also works).
4. Open **Git Bash** or a WSL terminal in this folder. The scripts are Bash scripts and are not native PowerShell scripts.

## Start BLUE

```bash
docker compose up -d --build blue nginx
docker compose ps
bash scripts/smoke_test.sh
```

Open `http://localhost:8080/version`. It should report `blue-v1`.

## Continuous traffic + deploy

**Terminal 1 — run the traffic generator:**

```bash
DURATION=120 bash scripts/traffic_test.sh
```

**Terminal 2 — deploy GREEN while traffic is running:**

```bash
bash scripts/deploy.sh green-v2
```

Watch terminal 1. It should report `failed=0` for a successful local run. Check `traffic.log` for timestamps, HTTP status, and which model version answered each request.

After deployment:

```bash
curl -s http://localhost:8080/version
docker compose ps -a
```

The endpoint should report `green-v2`; BLUE is stopped but retained so you can roll back.

## Roll back

```bash
bash scripts/rollback.sh
curl -s http://localhost:8080/version
```

The endpoint should report `blue-v1`.

## Test GREEN startup failure

Stop the current setup and restart baseline BLUE:

```bash
bash scripts/rollback.sh
```

Then in Git Bash, force GREEN readiness to fail for a deployment test:

```bash
GREEN_MODEL_LOAD_FAIL=true bash scripts/deploy.sh green-failing-v3
```

Compose environment substitution comes from the shell only if exported to Compose. For reliable injection, use:

```bash
export GREEN_MODEL_LOAD_FAIL=true
bash scripts/deploy.sh green-failing-v3
unset GREEN_MODEL_LOAD_FAIL
```

Expected: GREEN does not become healthy; deployment aborts and BLUE keeps serving. Confirm with `curl -s http://localhost:8080/version`.

## Useful commands

```bash
docker compose logs -f nginx
docker logs -f credit-blue
docker logs -f credit-green
docker compose ps -a
docker compose down
```

## Notes and limitations

- NGINX reload is graceful: existing NGINX workers can finish in-flight connections while new workers use the updated config. The script also gives the old model container a 35-second shutdown grace period.
- A zero-failure result is empirical for the tested local workload, not a mathematical guarantee. Real production systems need load testing, observability, compatible model/API versions, capacity planning, and tested failure recovery.
- This demo uses static Docker service DNS names. `nginx -t` validates syntax, but does not prove upstream reachability; post-switch requests verify that GREEN actually serves traffic.
- Keep the prior container and configuration until the new version has passed an observation window.
- For production, consider a versioned config directory, automated rollback on latency/error thresholds, Docker secrets, authentication, TLS, structured logs, and a real validated model with fairness and compliance review.
