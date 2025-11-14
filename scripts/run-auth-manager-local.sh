#!/usr/bin/env bash
set -euo pipefail

ROOT=${ROOT:-$(git rev-parse --show-toplevel)}
RESULT_LINK=${RESULT_LINK:-$ROOT/result-auth-manager}
LOG_PATH=${LOG_PATH:-$ROOT/run/auth-manager-local.log}
PID_PATH=${PID_PATH:-$ROOT/run/auth-manager-local.pid}
PORT=${PORT:-18088}
LISTEN_ADDR=${LISTEN_ADDR:-127.0.0.1:${PORT}}
STARTUP_TIMEOUT=${STARTUP_TIMEOUT:-30}
POLL_INTERVAL=${POLL_INTERVAL:-1}
TEARDOWN_ON_EXIT=${TEARDOWN_ON_EXIT:-false}

mkdir -p "$ROOT/run"

if [[ ! -x "$RESULT_LINK/bin/auth-manager" ]]; then
  echo "[auth-manager] building binary via nix build .#auth-manager"
  nix build "$ROOT"#auth-manager -o "$RESULT_LINK"
fi

if lsof -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "[auth-manager] existing process on port $PORT detected; terminating"
  lsof -iTCP:"$PORT" -sTCP:LISTEN -t | xargs -r kill || true
  sleep 1
fi

: > "$LOG_PATH"

env \
  AUTH_MANAGER_LISTEN_ADDR="$LISTEN_ADDR" \
  AUTH_MANAGER_SIGNING_KEY="${AUTH_MANAGER_SIGNING_KEY:-local-testing-signing-key}" \
  AUTH_MANAGER_POMERIUM_SHARED_SECRET="${AUTH_MANAGER_POMERIUM_SHARED_SECRET:-local-testing-shared-secret}" \
  AUTH_MANAGER_MATTERMOST_URL="${AUTH_MANAGER_MATTERMOST_URL:-http://127.0.0.1:8065}" \
  AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN="${AUTH_MANAGER_MATTERMOST_ADMIN_TOKEN:-dummy-admin-token}" \
  AUTH_MANAGER_SOURCE_IDP="${AUTH_MANAGER_SOURCE_IDP:-gitlab}" \
  AUTH_MANAGER_DATABASE_URL="${AUTH_MANAGER_DATABASE_URL:-}" \
  nohup "$RESULT_LINK/bin/auth-manager" >>"$LOG_PATH" 2>&1 &
PID=$!

echo "[auth-manager] started PID $PID, log=$LOG_PATH"

echo "$PID" > "$PID_PATH"

cleanup() {
  if [[ "$TEARDOWN_ON_EXIT" == "true" ]] && kill -0 "$PID" 2>/dev/null; then
    echo "[auth-manager] tearing down PID $PID"
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

elapsed=0
while true; do
  if curl --fail --silent "http://$LISTEN_ADDR/healthz" >/dev/null 2>&1; then
    echo "[auth-manager] healthy after ${elapsed}s (PID $PID)"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "[auth-manager] process exited unexpectedly"
    tail -n 100 "$LOG_PATH" >&2
    exit 1
  fi
  if (( elapsed >= STARTUP_TIMEOUT )); then
    echo "[auth-manager] timeout waiting for healthz"
    tail -n 100 "$LOG_PATH" >&2
    exit 1
  fi
  sleep "$POLL_INTERVAL"
  elapsed=$((elapsed + POLL_INTERVAL))
  echo "[auth-manager] waiting... (${elapsed}s)"
done
