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

test_timeout_is_failed_and_group_killed() {
  start=$(date +%s)
  "$RUNNER" --id to --workdir "$WORK" --timeout 2 -- bash -c 'sleep 30 & echo $! > "$RUNNER_RUN_DIR/child"; while :; do echo tick; sleep 0.1; done'; rc=$?
  assert_eq "$rc" 1
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/to/status")" failed
  assert_contains "$RUNNER_RUNS_ROOT/to/reason" timeout
  [ $(( $(date +%s) - start )) -lt 10 ] || fail "took too long"
  child=$(cat "$RUNNER_RUNS_ROOT/to/child")
  sleep 0.5; ! kill -0 "$child" 2>/dev/null || fail "child $child still alive"
}

test_stall_when_log_and_git_idle() {
  "$RUNNER" --id st --workdir "$WORK" --stall-minutes 2 -- bash -c 'echo start; sleep 30'; rc=$?
  assert_eq "$rc" 1
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/st/status")" failed
  assert_contains "$RUNNER_RUNS_ROOT/st/reason" stall
}

test_no_stall_while_log_active() {
  "$RUNNER" --id ok --workdir "$WORK" --stall-minutes 2 -- bash -c 'for i in 1 2 3 4 5 6 7 8; do echo $i; sleep 0.5; done'; rc=$?
  assert_eq "$rc" 0
}

test_git_activity_prevents_stall() {
  git -C "$WORK" init -q
  "$RUNNER" --id g --workdir "$WORK" --stall-minutes 2 -- bash -c 'for i in 1 2 3 4 5 6; do echo $i > f$i; sleep 0.7; done' >/dev/null; rc=$?
  assert_eq "$rc" 0
}

test_expect_present_is_done() {
  "$RUNNER" --id e1 --workdir "$WORK" --expect out.md -- bash -c 'echo hello > "$RUNNER_RUN_DIR/out.md"'; rc=$?
  assert_eq "$rc" 0
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/e1/status")" done
}

test_expect_empty_is_blocked() {
  "$RUNNER" --id e2 --workdir "$WORK" --expect out.md -- true; rc=$?
  assert_eq "$rc" 2
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/e2/status")" blocked
  assert_contains "$RUNNER_RUNS_ROOT/e2/reason" "expect"
}

test_expect_missing_nested_is_blocked() {
  "$RUNNER" --id e3 --workdir "$WORK" --expect sub/result.json -- true; rc=$?
  assert_eq "$rc" 2
}

test_expect_rejects_escape() {
  "$RUNNER" --id e4 --workdir "$WORK" --expect ../x -- true; rc=$?
  assert_eq "$rc" 4
  "$RUNNER" --id e5 --workdir "$WORK" --expect /etc/passwd -- true; rc=$?
  assert_eq "$rc" 4
}

test_engine_failure_beats_expect() {
  "$RUNNER" --id e6 --workdir "$WORK" --expect out.md -- bash -c 'exit 3'; rc=$?
  assert_eq "$rc" 1
}

test_wake_posts_json() {
  port=$(( 20000 + RANDOM % 20000 ))
  python3 - "$port" "$T/wake.json" <<'PY' &
import http.server, sys
port, out = int(sys.argv[1]), sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0)); open(out, 'wb').write(self.rfile.read(n))
        self.send_response(204); self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', port), H).handle_request()
PY
  srv=$!; sleep 0.5
  "$RUNNER" --id w1 --workdir "$WORK" --expect out.md --wake-url "http://127.0.0.1:$port/hook?k=s" -- bash -c 'echo x > "$RUNNER_RUN_DIR/out.md"'
  wait "$srv"
  assert_eq "$(jq -r .id "$T/wake.json")" w1
  assert_eq "$(jq -r .status "$T/wake.json")" done
  assert_eq "$(jq -r .run_dir "$T/wake.json")" "$RUNNER_RUNS_ROOT/w1"
  assert_eq "$(jq -r .expect_path "$T/wake.json")" "$RUNNER_RUNS_ROOT/w1/out.md"
}

test_wake_failure_does_not_change_status() {
  "$RUNNER" --id w2 --workdir "$WORK" --wake-url "http://127.0.0.1:1/none" -- true; rc=$?
  assert_eq "$rc" 0
  assert_contains "$RUNNER_RUNS_ROOT/w2/log" "wake failed"
}

run_tests "${1:-}"
