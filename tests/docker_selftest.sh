#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes are intentional: expanded inside the container
# Build the image (without Cursor CLI) and prove runner works in-container.
set -euo pipefail
cd "$(dirname "$0")/.."
IMG=agent-host:selftest
docker build --build-arg INSTALL_CURSOR=0 -t "$IMG" .

run() { docker run --rm "$IMG" bash -lc "$1"; }

# done path
run 'mkdir -p /work/repo && runner --id ok --expect out.md -- bash -c "echo hi > \"\$RUNNER_RUN_DIR/out.md\"" && test "$(cat ~/.runner-runs/ok/status)" = "done"'
echo "selftest: done ok"

# blocked path
set +e
run 'mkdir -p /work/repo && runner --id b --expect out.md -- true'; rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "expected 2 got $rc"; exit 1; }
echo "selftest: blocked ok"

# timeout path (RUNNER_MINUTE_SECS shrinks minutes to seconds)
set +e
docker run --rm -e RUNNER_MINUTE_SECS=1 "$IMG" bash -lc 'mkdir -p /work/repo && runner --id t --timeout 2 -- sleep 30'; rc=$?
set -e
[ "$rc" -eq 1 ] || { echo "expected 1 got $rc"; exit 1; }
echo "selftest: timeout ok"

# entrypoint passthrough + non-root user
user="$(docker run --rm "$IMG" id -un)"
[ "$user" = agent ] || { echo "expected user agent got $user" >&2; exit 1; }
echo "selftest: user ok"
echo "selftest: PASS"
