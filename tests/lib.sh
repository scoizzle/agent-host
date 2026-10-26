#!/usr/bin/env bash
# Minimal test harness: functions named test_* are discovered and run.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/runner"
TMP_BASE="$ROOT/tests/.tmp"
FAILS=0; PASSES=0

fail() { echo "    FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "expected [$2] got [$1] ${3:-}"; }
assert_file_nonempty() { [ -s "$1" ] || fail "expected non-empty file $1"; }
assert_file_exists() { [ -e "$1" ] || fail "expected file $1"; }
assert_contains() { grep -q -- "$2" "$1" || fail "expected $1 to contain [$2]"; }

setup() {
  T="$(mktemp -d "$TMP_BASE/t.XXXXXX")"
  export RUNNER_RUNS_ROOT="$T/runs" RUNNER_MINUTE_SECS=1 RUNNER_POLL_SECS=0.2
  mkdir -p "$T/work"; WORK="$T/work"
}

run_tests() {
  mkdir -p "$TMP_BASE"
  local filter="${1:-}" t
  for t in $(declare -F | awk '{print $3}' | grep '^test_' | grep -- "$filter"); do
    setup
    if ( set -e; "$t" ); then PASSES=$((PASSES+1)); echo "ok   $t"
    else FAILS=$((FAILS+1)); echo "FAIL $t"; fi
    rm -rf "$T"
  done
  echo "passed=$PASSES failed=$FAILS"
  [ "$FAILS" -eq 0 ]
}
