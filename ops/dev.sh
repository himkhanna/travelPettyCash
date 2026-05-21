#!/usr/bin/env bash
# Dev loop helper for the PDD Petty Cash backend.
# Subcommands: up | down | restart | status | logs | smoke | help
# Default with no args = restart (stop -> build -> start -> verify).

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/ops/docker-compose.yml"
BACKEND_DIR="$REPO_ROOT/backend"
LOG_FILE="${PETTYCASH_LOG:-/tmp/pettycash-backend.log}"
PORT="${PETTYCASH_PORT:-8080}"
PROFILE="${PETTYCASH_PROFILE:-local}"
BOOT_TIMEOUT_SECONDS="${PETTYCASH_BOOT_TIMEOUT:-180}"
DB_HEALTH_TIMEOUT_SECONDS="${PETTYCASH_DB_TIMEOUT:-60}"

# ANSI colors (auto-disabled when not a tty)
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

log()  { echo "${C_BLUE}==>${C_RESET} $*"; }
ok()   { echo "${C_GREEN}OK${C_RESET}  $*"; }
warn() { echo "${C_YELLOW}!!${C_RESET}  $*" >&2; }
err()  { echo "${C_RED}XX${C_RESET}  $*" >&2; }

# ---------------------------------------------------------------------------
# Probes
# ---------------------------------------------------------------------------
backend_pid() {
  # Find the *running* Spring Boot JVM, not gradle wrappers.
  pgrep -f "ae.gov.pdd.pettycash.PettyCashApplication" 2>/dev/null | head -1 || true
}

port_listener_pids() {
  lsof -t -i ":$PORT" 2>/dev/null || true
}

compose_up_and_healthy() {
  local pg_status minio_status
  pg_status=$(docker inspect -f '{{.State.Health.Status}}' travelpettycash-postgres 2>/dev/null || echo missing)
  minio_status=$(docker inspect -f '{{.State.Health.Status}}' travelpettycash-minio 2>/dev/null || echo missing)
  [ "$pg_status" = "healthy" ] && [ "$minio_status" = "healthy" ]
}

backend_responding() {
  curl -fsS --max-time 2 "http://localhost:$PORT/health" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
ensure_compose() {
  if compose_up_and_healthy; then
    ok "Postgres + MinIO already healthy"
    return
  fi
  log "Starting Postgres + MinIO ($COMPOSE_FILE)"
  docker compose -f "$COMPOSE_FILE" up -d >/dev/null
  log "Waiting up to ${DB_HEALTH_TIMEOUT_SECONDS}s for healthy"
  local deadline=$((SECONDS + DB_HEALTH_TIMEOUT_SECONDS))
  until compose_up_and_healthy; do
    if [ $SECONDS -ge $deadline ]; then
      err "Postgres / MinIO did not become healthy in ${DB_HEALTH_TIMEOUT_SECONDS}s"
      docker ps --format 'table {{.Names}}\t{{.Status}}' | grep travelpettycash || true
      exit 1
    fi
    sleep 2
  done
  ok "Postgres + MinIO healthy"
}

stop_backend() {
  local pid listeners
  pid=$(backend_pid)
  if [ -n "$pid" ]; then
    log "Stopping backend (pid $pid)"
    kill "$pid" 2>/dev/null || true
    # Wait up to 10s for graceful shutdown.
    for _ in $(seq 1 10); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      warn "Backend did not exit in 10s — sending SIGKILL"
      kill -9 "$pid" 2>/dev/null || true
    fi
  else
    log "No running backend"
  fi
  # Kill any straggling gradle wrappers, and anything still squatting on the port.
  pkill -f "GradleWrapperMain.*bootRun" 2>/dev/null || true
  listeners=$(port_listener_pids)
  if [ -n "$listeners" ]; then
    warn "Killing stale listeners on port $PORT: $listeners"
    echo "$listeners" | xargs -r kill -9 2>/dev/null || true
  fi
  ok "Backend stopped"
}

build_backend() {
  log "Building backend (./gradlew build -x test)"
  (cd "$BACKEND_DIR" && ./gradlew --console=plain -q build -x test) \
    || { err "Build failed"; exit 1; }
  ok "Build succeeded"
}

start_backend() {
  if [ -n "$(backend_pid)" ]; then
    warn "Backend already running (pid $(backend_pid))"
    return
  fi
  log "Starting backend (profile=$PROFILE, log=$LOG_FILE)"
  (
    cd "$BACKEND_DIR"
    nohup ./gradlew --console=plain -q bootRun \
      --args="--spring.profiles.active=$PROFILE" \
      > "$LOG_FILE" 2>&1 &
    disown
  )
  log "Waiting up to ${BOOT_TIMEOUT_SECONDS}s for 'Started PettyCashApplication'"
  local deadline=$((SECONDS + BOOT_TIMEOUT_SECONDS))
  until grep -qE "Started PettyCashApplication|APPLICATION FAILED|BUILD FAILED|Application run failed|Web server failed to start" "$LOG_FILE" 2>/dev/null; do
    if [ $SECONDS -ge $deadline ]; then
      err "Backend did not signal readiness in ${BOOT_TIMEOUT_SECONDS}s"
      tail -30 "$LOG_FILE" >&2
      exit 1
    fi
    sleep 2
  done
  if grep -qE "APPLICATION FAILED|BUILD FAILED|Application run failed|Web server failed to start" "$LOG_FILE"; then
    err "Backend failed to start. Last 30 log lines:"
    tail -30 "$LOG_FILE" >&2
    exit 1
  fi
  ok "Backend up on http://localhost:$PORT"
}

smoke() {
  log "Smoke test"
  local fail=0
  if backend_responding; then
    ok "/health responds"
  else
    err "/health is not reachable on port $PORT"
    return 1
  fi
  local token me trips
  token=$(curl -fsS -X POST "http://localhost:$PORT/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"provider":"PDD_SSO","code":"any"}' \
    | python3 -c 'import json,sys;print(json.load(sys.stdin).get("accessToken",""))' 2>/dev/null) || true
  if [ -z "$token" ]; then
    err "Login did not return an accessToken"
    return 1
  fi
  ok "Login OK (PDD_SSO → JWT issued)"
  me=$(curl -fsS "http://localhost:$PORT/api/v1/me" -H "Authorization: Bearer $token" \
    | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["username"]+" role="+d["role"])' 2>/dev/null) || fail=1
  if [ $fail -ne 0 ]; then err "/me failed with the issued token"; return 1; fi
  ok "/me → $me"
  trips=$(curl -fsS "http://localhost:$PORT/api/v1/trips?status=ACTIVE" \
    -H "Authorization: Bearer $token" \
    | python3 -c 'import json,sys;d=json.load(sys.stdin);print(str(len(d))+" active trip(s)")' 2>/dev/null) || fail=1
  if [ $fail -ne 0 ]; then err "/trips failed"; return 1; fi
  ok "/trips → $trips"
  echo "fake" > /tmp/pettycash-smoke.jpg
  local scan
  scan=$(curl -fsS -X POST "http://localhost:$PORT/api/v1/receipts/scan" \
    -H "Authorization: Bearer $token" \
    -F "file=@/tmp/pettycash-smoke.jpg;type=image/jpeg" \
    | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["vendor"]+" / conf="+str(d["confidence"]))' 2>/dev/null) || fail=1
  if [ $fail -ne 0 ]; then err "/receipts/scan failed"; return 1; fi
  ok "/receipts/scan → $scan"
  ok "All smoke checks passed"
}

status() {
  log "Compose"
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E "travelpettycash|NAMES" || true
  echo
  log "Backend process"
  local pid
  pid=$(backend_pid)
  if [ -n "$pid" ]; then
    ok "Running (pid $pid)"
    if backend_responding; then
      ok "/health responding on port $PORT"
    else
      warn "Process running but /health not responding yet"
    fi
  else
    warn "Not running"
  fi
  echo
  log "Port $PORT listeners"
  lsof -i ":$PORT" 2>/dev/null | head -5 || echo "  (none)"
  echo
  log "Last 5 lines of $LOG_FILE"
  [ -f "$LOG_FILE" ] && tail -5 "$LOG_FILE" || echo "  (no log yet)"
}

logs_cmd() {
  if [ ! -f "$LOG_FILE" ]; then
    err "No log at $LOG_FILE"
    exit 1
  fi
  exec tail -f "$LOG_FILE"
}

help() {
  cat <<EOF
Usage: ops/dev.sh [command]

Commands:
  up         Bring up compose + backend, then smoke test.
  down       Stop the backend (compose stays up).
  nuke       Stop the backend AND stop/remove the compose stack and volumes.
  restart    Stop -> build -> start -> smoke test. (default)
  build      Just rebuild the backend jar.
  status     Show what's running.
  logs       Tail the backend log.
  smoke      Run the smoke test against whatever is already running.
  help       This message.

Environment:
  PETTYCASH_PORT          (default 8080)
  PETTYCASH_PROFILE       (default local)
  PETTYCASH_LOG           (default /tmp/pettycash-backend.log)
  PETTYCASH_BOOT_TIMEOUT  (default 180 seconds)
  PETTYCASH_DB_TIMEOUT    (default 60 seconds)
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
cmd="${1:-restart}"
case "$cmd" in
  up)
    ensure_compose
    start_backend
    smoke
    ;;
  down)
    stop_backend
    ;;
  nuke)
    stop_backend
    log "Removing compose stack + volumes"
    docker compose -f "$COMPOSE_FILE" down -v >/dev/null
    ok "Compose stack removed"
    ;;
  restart)
    stop_backend
    ensure_compose
    build_backend
    start_backend
    smoke
    ;;
  build)
    build_backend
    ;;
  status)
    status
    ;;
  logs)
    logs_cmd
    ;;
  smoke)
    smoke
    ;;
  help|-h|--help)
    help
    ;;
  *)
    err "Unknown command: $cmd"
    help
    exit 2
    ;;
esac
