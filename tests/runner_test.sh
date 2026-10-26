#!/usr/bin/env bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

test_done_creates_run_dir_and_status() {
  "$RUNNER" --id t1 --workdir "$WORK" -- bash -c 'echo hi' ; rc=$?
  assert_eq "$rc" 0
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/t1/status")" done
  assert_file_exists "$RUNNER_RUNS_ROOT/t1/out.md"
  assert_contains "$RUNNER_RUNS_ROOT/t1/log" hi
}

test_engine_failure_is_failed() {
  "$RUNNER" --id t2 --workdir "$WORK" -- bash -c 'exit 7'; rc=$?
  assert_eq "$rc" 1
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/t2/status")" failed
  assert_contains "$RUNNER_RUNS_ROOT/t2/reason" "exit 7"
}

test_env_exported_to_engine() {
  "$RUNNER" --id t3 --workdir "$WORK" -- bash -c 'echo "$RUNNER_ID $RUNNER_RUN_DIR" > "$RUNNER_RUN_DIR/out.md"; pwd >> "$RUNNER_RUN_DIR/out.md"'
  assert_eq "$(sed -n 1p "$RUNNER_RUNS_ROOT/t3/out.md")" "t3 $RUNNER_RUNS_ROOT/t3"
  assert_eq "$(sed -n 2p "$RUNNER_RUNS_ROOT/t3/out.md")" "$WORK"
}

test_unknown_flag_is_usage() {
  "$RUNNER" --bogus -- true; rc=$?
  assert_eq "$rc" 4
}

test_missing_command_is_usage() {
  "$RUNNER" --id t5 --workdir "$WORK"; rc=$?
  assert_eq "$rc" 4
}

test_missing_workdir_is_usage() {
  "$RUNNER" --id t6 --workdir "$T/nope" -- true; rc=$?
  assert_eq "$rc" 4
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/t6/status")" usage
}

test_existing_id_is_usage() {
  "$RUNNER" --id dup --workdir "$WORK" -- true
  "$RUNNER" --id dup --workdir "$WORK" -- true; rc=$?
  assert_eq "$rc" 4
}

test_default_id_is_timestamp_slug() {
  "$RUNNER" --workdir "$WORK" -- true
  ls "$RUNNER_RUNS_ROOT" | grep -Eq '^[0-9]{8}-[0-9]{6}-[0-9a-f]{4}$'
}

run_tests "${1:-}"
