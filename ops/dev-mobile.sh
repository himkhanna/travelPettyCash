#!/usr/bin/env bash
# Dev loop helper for the PDD Petty Cash Flutter app.
# Subcommands: up | analyze | test | check | build | clean | pub | help
# Default with no args = up (pub get, then run -d chrome).

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOBILE_DIR="$REPO_ROOT/mobile"
DEVICE="${PETTYCASH_MOBILE_DEVICE:-chrome}"
WEB_PORT="${PETTYCASH_MOBILE_WEB_PORT:-}"
API_BASE="${PETTYCASH_API_BASE:-}"      # optional dart-define override

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
# Prerequisites
# ---------------------------------------------------------------------------
require_flutter() {
  if ! command -v flutter >/dev/null 2>&1; then
    err "flutter not found on PATH"
    err "Install: https://docs.flutter.dev/get-started/install"
    err "Or set FLUTTER_ROOT and prepend \$FLUTTER_ROOT/bin to PATH"
    exit 127
  fi
}

show_flutter_version() {
  local v
  v=$(flutter --version 2>/dev/null | head -1 || echo "?")
  log "$v"
}

# Optional --dart-define flags built from env.
dart_defines() {
  local flags=()
  if [ -n "$API_BASE" ]; then
    flags+=("--dart-define=API_BASE=$API_BASE")
  fi
  printf '%s ' "${flags[@]}"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
pub_get() {
  log "flutter pub get"
  (cd "$MOBILE_DIR" && flutter pub get) || { err "pub get failed"; exit 1; }
  ok "Dependencies resolved"
}

analyze() {
  log "flutter analyze --no-fatal-infos"
  if (cd "$MOBILE_DIR" && flutter analyze --no-fatal-infos); then
    ok "analyze clean"
  else
    err "analyze reported issues"
    return 1
  fi
}

run_tests() {
  log "flutter test"
  if (cd "$MOBILE_DIR" && flutter test); then
    ok "tests passed"
  else
    err "tests failed"
    return 1
  fi
}

check() {
  pub_get
  analyze
  run_tests
  ok "All checks passed"
}

build_web() {
  pub_get
  log "flutter build web --release"
  local extra
  extra=$(dart_defines)
  # shellcheck disable=SC2086 -- intentional word-splitting on dart-define flags
  (cd "$MOBILE_DIR" && flutter build web --release $extra) \
    || { err "Web build failed"; exit 1; }
  ok "Built mobile/build/web (deployable artifact)"
}

clean() {
  log "flutter clean"
  (cd "$MOBILE_DIR" && flutter clean) >/dev/null
  ok "Cleaned mobile/.dart_tool + mobile/build"
}

up() {
  pub_get
  log "flutter run -d $DEVICE"
  if [ -n "$API_BASE" ]; then
    log "Wiring real backend: API_BASE=$API_BASE"
  else
    log "Running against fake repositories (no backend needed)"
    log "Set PETTYCASH_API_BASE=http://localhost:8080 to hit the real backend once that wiring lands"
  fi
  local port_arg=""
  if [ -n "$WEB_PORT" ]; then
    port_arg="--web-port=$WEB_PORT"
  fi
  local extra
  extra=$(dart_defines)
  # Exec so Ctrl-C in flutter run propagates cleanly to the script.
  # shellcheck disable=SC2086
  exec env -C "$MOBILE_DIR" flutter run -d "$DEVICE" $port_arg $extra
}

help() {
  cat <<EOF
Usage: ops/dev-mobile.sh [command]

Commands:
  up         pub get, then flutter run -d \$DEVICE (blocking). Default.
  pub        flutter pub get only.
  analyze    flutter analyze --no-fatal-infos.
  test       flutter test.
  check      pub get + analyze + test (the CI parity loop).
  build      flutter build web --release. Output: mobile/build/web.
  clean      flutter clean.
  help       This message.

Environment:
  PETTYCASH_MOBILE_DEVICE    Target device id (default: chrome).
                             Try 'flutter devices' for what's available.
  PETTYCASH_MOBILE_WEB_PORT  Pin a fixed port for chrome (default: random).
  PETTYCASH_API_BASE         If set, passed to the app as
                             --dart-define=API_BASE=<value>. Today the
                             app ignores this and always uses fakes;
                             once the real-API switch lands it will
                             flip the repos over.

Examples:
  ops/dev-mobile.sh                          # fake mode, random port
  ops/dev-mobile.sh up                       # same as above
  PETTYCASH_MOBILE_WEB_PORT=5000 ops/dev-mobile.sh up
  PETTYCASH_API_BASE=http://localhost:8080 ops/dev-mobile.sh up
  ops/dev-mobile.sh check                    # full pre-push gate
  ops/dev-mobile.sh build                    # for the Vercel preview
EOF
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
cmd="${1:-up}"
case "$cmd" in
  help|-h|--help) help; exit 0 ;;
esac
require_flutter
case "$cmd" in
  up)      show_flutter_version; up ;;
  pub)     show_flutter_version; pub_get ;;
  analyze) show_flutter_version; analyze ;;
  test)    show_flutter_version; run_tests ;;
  check)   show_flutter_version; check ;;
  build)   show_flutter_version; build_web ;;
  clean)   show_flutter_version; clean ;;
  *)
    err "Unknown command: $cmd"
    help
    exit 2
    ;;
esac
