#!/usr/bin/env bash
# Default: register this container as a Cursor Personal machine.
# Anything other than "worker" runs as a one-off command (login, shell, runner).
set -euo pipefail

if [ "${1:-worker}" != worker ]; then exec "$@"; fi

: "${WORKER_NAME:?set WORKER_NAME}"
REPO_DIR=${REPO_DIR:-/work/repo}

if [ ! -d "$REPO_DIR/.git" ]; then
  if [ -n "${REPO_URL:-}" ]; then
    git clone "$REPO_URL" "$REPO_DIR"
  else
    mkdir -p "$REPO_DIR" && git -C "$REPO_DIR" init -q
  fi
fi

args=(--name "$WORKER_NAME" --worker-dir "$REPO_DIR")
[ -n "${MAX_AGENTS:-}" ] && args+=(--max-agents "$MAX_AGENTS")
[ -n "${WORKER_DEBUG_FILE:-}" ] && args+=(--debug-file "$WORKER_DEBUG_FILE")

# Background + forward SIGTERM/SIGINT so the CLI disconnects cleanly.
cursor-agent worker start "${args[@]}" &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid"; exit $?' TERM INT
wait "$pid"
