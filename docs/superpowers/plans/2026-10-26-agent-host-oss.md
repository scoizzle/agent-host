# agent-host OSS v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a public, Poly-free repo `scoizzle/agent-host`. With it, anyone can clone, run `docker compose up`, see the container register as a Cursor Personal machine, launch one cheap Cloud Agent that calls `runner`, and watch the job finish.

**Architecture:** A Docker worker (Ubuntu 24.04, user `agent`, tini as PID 1) runs `cursor-agent worker start` in machine mode and forwards SIGTERM so the worker disconnects cleanly. A bash `runner` CLI at `/usr/local/bin/runner` supervises one job:
- creates the run folder `~/.runner-runs/<id>/`
- starts an engine adapter in its own process group (`shell` works in v1; `grok` and `opencode` are stubs)
- watches for exit, timeout, or stall (log idle and git idle)
- applies the `--expect` gate, which is relative to the run folder
- writes `status` and `reason`
- optionally POSTs a wake webhook
- exits with a mapped code

The Cloud Agent only orchestrates: it runs `runner` and then exits.

**Tech Stack:** Bash 5, coreutils (`stat`, `setsid`, `timeout`), `jq`, `curl`, git, Docker / Docker Compose v2, tini, Cursor CLI (`cursor-agent`), and GitHub Actions. Tests are a plain-bash assertion harness with no bats dependency.

## Global Constraints

- **No Poly in core.** Do not include mill templates, opposite-mill rules, allow-path, PR push, Roslynk, .NET SDK or heap knobs, `fill-prompt.sh`, or `REPO_URL` defaults that point at Poly.
- **Exit codes are fixed:** `0` done, `1` failed, `2` blocked, `3` partial, `4` usage.
- **Status words are fixed:** `running`, `done`, `failed`, `blocked`, `partial`, `usage`. The `status` file holds exactly one word and a newline. The human-readable reason goes in the `reason` sidecar file.
- **Stall and timeout map to `failed`.** The reason is `timeout` or `stall`.
- **A missing or empty `--expect` maps to `blocked`,** never `partial`. `partial` is reserved and no v1 code path writes it.
- **`--expect` is relative to the run folder.** Reject absolute paths and paths that contain `..` with `usage`.
- **Engines receive these env vars:** `RUNNER_RUN_DIR` (absolute path of the run folder) and `RUNNER_ID`.
- **Test hooks:**
  - `RUNNER_RUNS_ROOT` overrides `~/.runner-runs`.
  - `RUNNER_MINUTE_SECS` (default `60`) sets how many seconds count as one "minute" for `--timeout` and `--stall-minutes`.
  - `RUNNER_POLL_SECS` (default `1`) sets the watch poll interval.
- **License:** MIT, copyright 2026 Scot Murphy.
- **CI never needs Cursor login** and never runs a Cloud Agent.
- **Private source:** the private copies of `Dockerfile`, `compose.yaml`, `entrypoint.sh`, `.env.example`, `mill.sh`, and `fill-prompt.sh` sit **untracked** in the repo root. They came from Scot's private `~/agent-host` on scot-mac. Tasks 1 and 6 adapt them and delete what is Poly-only. If a newer private copy exists on scot-mac when you start, diff it against the root copies first and port any non-Poly fixes.

## File Structure

| Path | Action | Responsibility |
|------|--------|----------------|
| `LICENSE` | create | MIT text |
| `.gitignore` | create | `.env`, `tests/.tmp/` |
| `README.md` | rewrite | Quickstart, clone→job checklist, runner reference |
| `bin/runner` | create | Runner CLI (single bash file: parse, run dir, engines, watch, expect, wake, exit) |
| `tests/lib.sh` | create | Assertion helpers + test discovery |
| `tests/runner_test.sh` | create | Unit tests for runner (no Docker) |
| `tests/docker_selftest.sh` | create | Builds image, runs runner inside container (no Cursor login) |
| `Dockerfile` | rewrite | Ubuntu image: base tools, user `agent`, cursor-agent, runner, entrypoint |
| `entrypoint.sh` | rewrite | `worker` → `cursor-agent worker start` (machine mode) with SIGTERM forwarding; else exec args |
| `compose.yaml` | rewrite | One `worker` service, caps, named volumes (cursor, config, work), optional RO wake bind |
| `.env.example` | rewrite | Poly-free knobs |
| `engines/README.md` | create | Engine adapter contract + grok/opencode stub notes |
| `examples/hello-job/prompt.md` | create | Cloud Agent prompt |
| `examples/hello-job/README.md` | create | How to launch it and verify done |
| `.github/workflows/ci.yml` | create | shellcheck + unit + docker self-test jobs |
| `mill.sh`, `fill-prompt.sh` | delete (never commit) | Poly-only |

---

## Task 1: Repo scaffold

**Files:** create `LICENSE`, `.gitignore`, `README.md` (skeleton), `.github/workflows/ci.yml` (stub). Delete `mill.sh` and `fill-prompt.sh`.

- [ ] **Step 1: Remove the Poly-only files.** They are untracked, so `rm` is enough:

```bash
cd /workspace/agent-host && rm -f mill.sh fill-prompt.sh && git status --short
```

Expected: only `.env.example`, `Dockerfile`, `README.md`, `compose.yaml`, and `entrypoint.sh` remain as `??`.

- [ ] **Step 2: Write `LICENSE`:**

```text
MIT License

Copyright (c) 2026 Scot Murphy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 3: Write `.gitignore`:**

```gitignore
.env
tests/.tmp/
```

- [ ] **Step 4: Overwrite `README.md` with this skeleton.** Task 7 fills it in:

```markdown
# agent-host

Self-hosted Cursor worker in Docker plus `runner`, a small job supervisor.
A cheap Cursor Cloud Agent orchestrates; `runner` does the durable work.

Status: v1 in progress. See `docs/superpowers/specs/2026-10-26-agent-host-oss-design.md`.

License: MIT.
```

- [ ] **Step 5: Write the stub `.github/workflows/ci.yml`.** Task 8 replaces it:

```yaml
name: ci
on: [push, pull_request]
jobs:
  placeholder:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - run: echo "ci scaffold"
```

- [ ] **Step 6: Commit:**

```bash
git add LICENSE .gitignore README.md .github/workflows/ci.yml && git commit -m "chore: repo scaffold (MIT, gitignore, README, CI stub)"
```

Expected: one commit; `Dockerfile`, `compose.yaml`, `entrypoint.sh`, and `.env.example` are still untracked.

---

## Task 2: `runner` core — parse, run dir, status, exit codes, env

**Files:** create `tests/lib.sh`, `tests/runner_test.sh`, `bin/runner`.

- [ ] **Step 1: Write `tests/lib.sh`:**

```bash
#!/usr/bin/env bash
# Minimal test harness: functions named test_* are discovered and run.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/bin/runner"
TMP_BASE="$ROOT/tests/.tmp"
FAILS=0; PASSES=0

fail() { echo "    FAIL: $*" >&2; return 1; }
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
```

- [ ] **Step 2: Write failing tests in `tests/runner_test.sh`:**

```bash
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
```

- [ ] **Step 3: Run the tests and confirm they fail:**

```bash
chmod +x tests/runner_test.sh && bash tests/runner_test.sh
```

Expected: every test prints `FAIL` because `bin/runner` does not exist yet, and the last line reads `passed=0 failed=8`.

- [ ] **Step 4: Write `bin/runner`.** This is the full v1 skeleton. In this version the `run_engine` function is synchronous; Task 3 replaces it.

```bash
#!/usr/bin/env bash
# runner — supervise one job. See README "runner reference".
set -uo pipefail

EXIT_DONE=0 EXIT_FAILED=1 EXIT_BLOCKED=2 EXIT_PARTIAL=3 EXIT_USAGE=4
RUNS_ROOT="${RUNNER_RUNS_ROOT:-$HOME/.runner-runs}"
MINUTE_SECS="${RUNNER_MINUTE_SECS:-60}"
POLL_SECS="${RUNNER_POLL_SECS:-1}"

ID="" ENGINE=shell WORKDIR=/work/repo TIMEOUT_MIN=0 STALL_MIN=0 EXPECT="" WAKE_URL=""
CMD=() RUN_DIR="" ENGINE_RC=0 FAIL_REASON=""

usage_text() {
  cat <<'EOF'
usage: runner [--id NAME] [--engine shell|grok|opencode]
              [--workdir PATH] [--timeout MIN] [--stall-minutes N]
              [--expect RELPATH] [--wake-url URL] -- <command...>
exit: 0 done, 1 failed, 2 blocked, 3 partial, 4 usage
EOF
}

die_usage() {  # $1 message; writes status if run dir exists
  echo "runner: $1" >&2; usage_text >&2
  if [ -n "$RUN_DIR" ] && [ -d "$RUN_DIR" ]; then
    echo usage > "$RUN_DIR/status"; echo "$1" > "$RUN_DIR/reason"
  fi
  exit "$EXIT_USAGE"
}

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) ID="${2:-}"; shift 2 || die_usage "--id needs a value" ;;
      --engine) ENGINE="${2:-}"; shift 2 || die_usage "--engine needs a value" ;;
      --workdir) WORKDIR="${2:-}"; shift 2 || die_usage "--workdir needs a value" ;;
      --timeout) TIMEOUT_MIN="${2:-}"; shift 2 || die_usage "--timeout needs a value" ;;
      --stall-minutes) STALL_MIN="${2:-}"; shift 2 || die_usage "--stall-minutes needs a value" ;;
      --expect) EXPECT="${2:-}"; shift 2 || die_usage "--expect needs a value" ;;
      --wake-url) WAKE_URL="${2:-}"; shift 2 || die_usage "--wake-url needs a value" ;;
      -h|--help) usage_text; exit "$EXIT_DONE" ;;
      --) shift; CMD=("$@"); break ;;
      *) die_usage "unknown argument: $1" ;;
    esac
  done
  is_uint "$TIMEOUT_MIN" || die_usage "--timeout must be a whole number of minutes"
  is_uint "$STALL_MIN" || die_usage "--stall-minutes must be a whole number"
  if [ -n "$ID" ] && ! [[ "$ID" =~ ^[A-Za-z0-9._-]+$ ]]; then die_usage "--id must match [A-Za-z0-9._-]+"; fi
  if [ -n "$EXPECT" ]; then
    case "$EXPECT" in /*|..|../*|*/..|*/../*) die_usage "--expect must be relative to the run folder without .." ;; esac
  fi
  case "$ENGINE" in shell|grok|opencode) ;; *) die_usage "unsupported engine: $ENGINE" ;; esac
}

make_run_dir() {
  [ -n "$ID" ] || ID="$(date +%Y%m%d-%H%M%S)-$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n')"
  mkdir -p "$RUNS_ROOT"
  RUN_DIR="$RUNS_ROOT/$ID"
  if ! mkdir "$RUN_DIR" 2>/dev/null; then RUN_DIR=""; die_usage "run id already exists: $ID"; fi
  RUN_DIR="$(cd "$RUN_DIR" && pwd)"
  : > "$RUN_DIR/out.md"; : > "$RUN_DIR/log"; : > "$RUN_DIR/reason"
  printf '%q ' "${CMD[@]}" > "$RUN_DIR/cmd"; echo >> "$RUN_DIR/cmd"
  echo running > "$RUN_DIR/status"
}

validate_after_dir() {
  [ "${#CMD[@]}" -gt 0 ] || die_usage "missing command after --"
  [ -d "$WORKDIR" ] || die_usage "workdir does not exist: $WORKDIR"
}

# Sets ENGINE_RC and FAIL_REASON. Replaced in Task 3 with the watched version.
run_engine() {
  ( cd "$WORKDIR" && RUNNER_RUN_DIR="$RUN_DIR" RUNNER_ID="$ID" "${CMD[@]}" ) \
    </dev/null >>"$RUN_DIR/log" 2>&1
  ENGINE_RC=$?
  [ "$ENGINE_RC" -eq 0 ] || FAIL_REASON="engine exit $ENGINE_RC"
}

# Prints final status word. Replaced in Task 4 with expect gate.
decide_status() {
  if [ -n "$FAIL_REASON" ]; then echo failed; else echo done; fi
}

finish() {  # $1 status
  local st="$1" rc
  echo "$st" > "$RUN_DIR/status"
  [ -n "$FAIL_REASON" ] && echo "$FAIL_REASON" > "$RUN_DIR/reason"
  case "$st" in
    done) rc=$EXIT_DONE ;; failed) rc=$EXIT_FAILED ;; blocked) rc=$EXIT_BLOCKED ;;
    partial) rc=$EXIT_PARTIAL ;; *) rc=$EXIT_USAGE ;;
  esac
  echo "runner: id=$ID status=$st run_dir=$RUN_DIR" >&2
  exit "$rc"
}

main() {
  parse_args "$@"
  make_run_dir
  validate_after_dir
  run_engine
  finish "$(decide_status)"
}

main "$@"
```

- [ ] **Step 5: Run the tests and confirm they pass:**

```bash
chmod +x bin/runner && bash tests/runner_test.sh
```

Expected: `passed=8 failed=0`.

- [ ] **Step 6: Commit:**

```bash
git add bin/runner tests/lib.sh tests/runner_test.sh && git commit -m "feat(runner): arg parse, run dir, status file, exit codes, RUNNER_* env"
```

---

## Task 3: Watch loop — process group, timeout, stall

**Files:** modify `bin/runner` (replace `run_engine` and add helpers) and `tests/runner_test.sh` (append tests).

- [ ] **Step 1: Append failing tests to `tests/runner_test.sh`.** Insert them above the `run_tests` line:

```bash
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
```

- [ ] **Step 2: Run the new tests and confirm they fail:**

```bash
bash tests/runner_test.sh 'timeout\|stall\|git_activity'
```

Expected: `test_timeout_is_failed_and_group_killed` and `test_stall_when_log_and_git_idle` show `FAIL`. They return after 30 seconds with exit 0 because nothing watches the job yet. The other two show `ok`.

- [ ] **Step 3: In `bin/runner`, replace the whole `run_engine` function with this code and its helpers:**

```bash
now() { date +%s; }
mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }

git_fingerprint() {  # changes whenever HEAD or the working tree changes
  if git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
    { git -C "$WORKDIR" rev-parse HEAD 2>/dev/null; git -C "$WORKDIR" status --porcelain 2>/dev/null; } | md5sum | cut -d' ' -f1
  fi
}

kill_group() {  # $1 pgid
  kill -TERM -- "-$1" 2>/dev/null
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 -- "-$1" 2>/dev/null || return 0; sleep 0.2; done
  kill -KILL -- "-$1" 2>/dev/null
}

# Starts the engine in its own process group, watches it, sets ENGINE_RC / FAIL_REASON.
run_engine() {
  ( cd "$WORKDIR" && RUNNER_RUN_DIR="$RUN_DIR" RUNNER_ID="$ID" exec setsid "${CMD[@]}" ) \
    </dev/null >>"$RUN_DIR/log" 2>&1 &
  local pid=$! start last_act fp new_fp lm
  echo "$pid" > "$RUN_DIR/pid"
  trap 'kill_group "$pid"; FAIL_REASON="signal"; finish failed' TERM INT
  start=$(now); last_act=$start; fp="$(git_fingerprint)"; lm=$(mtime "$RUN_DIR/log")
  while kill -0 "$pid" 2>/dev/null; do
    sleep "$POLL_SECS"
    new_fp="$(git_fingerprint)"
    if [ "$(mtime "$RUN_DIR/log")" != "$lm" ] || [ "$new_fp" != "$fp" ] || [ -n "$(find "$RUN_DIR/log" -newermt "@$last_act" 2>/dev/null)" ]; then
      last_act=$(now); fp="$new_fp"; lm=$(mtime "$RUN_DIR/log")
    fi
    if [ "$TIMEOUT_MIN" -gt 0 ] && [ $(( $(now) - start )) -ge $(( TIMEOUT_MIN * MINUTE_SECS )) ]; then
      kill_group "$pid"; wait "$pid" 2>/dev/null; ENGINE_RC=124
      FAIL_REASON="timeout after ${TIMEOUT_MIN}m"; echo "runner: $FAIL_REASON" >>"$RUN_DIR/log"; return
    fi
    if [ "$STALL_MIN" -gt 0 ] && [ $(( $(now) - last_act )) -ge $(( STALL_MIN * MINUTE_SECS )) ]; then
      kill_group "$pid"; wait "$pid" 2>/dev/null; ENGINE_RC=125
      FAIL_REASON="stall: no log or git activity for ${STALL_MIN}m"; echo "runner: $FAIL_REASON" >>"$RUN_DIR/log"; return
    fi
  done
  wait "$pid"; ENGINE_RC=$?
  trap - TERM INT
  [ "$ENGINE_RC" -eq 0 ] || FAIL_REASON="engine exit $ENGINE_RC"
}
```

Notes:
- `setsid` makes the engine a process-group leader with `pgid == pid`, so `kill -- -pid` reaches every grandchild.
- `stat` mtime has 1-second resolution. The `find -newermt` check catches writes that land in the same second.

- [ ] **Step 4: Run the full suite and confirm it passes:**

```bash
bash tests/runner_test.sh
```

Expected: `passed=12 failed=0`. The run takes roughly 15 seconds or less.

- [ ] **Step 5: Commit:**

```bash
git add bin/runner tests/runner_test.sh && git commit -m "feat(runner): watch loop with timeout, log/git stall, process-group kill"
```

---

## Task 4: `--expect` gate → blocked, and the wake webhook

**Files:** modify `bin/runner` (replace `decide_status`, add `send_wake`, update `finish`) and `tests/runner_test.sh`.

- [ ] **Step 1: Append failing tests above `run_tests`:**

```bash
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
```

- [ ] **Step 2: Run the new tests and confirm they fail:**

```bash
bash tests/runner_test.sh 'expect\|wake'
```

Expected: `test_expect_empty_is_blocked`, `test_expect_missing_nested_is_blocked`, `test_wake_posts_json` (the server never gets a request, so it hangs; press Ctrl-C after about 5 seconds), and `test_wake_failure_does_not_change_status` fail. `test_expect_rejects_escape` already passes because Task 2 validates the path.

- [ ] **Step 3: In `bin/runner`, replace `decide_status` and `finish`, and add `send_wake`:**

```bash
# Prints final status word. Engine failure wins; then the --expect gate.
decide_status() {
  if [ -n "$FAIL_REASON" ]; then echo failed; return; fi
  if [ -n "$EXPECT" ] && [ ! -s "$RUN_DIR/$EXPECT" ]; then
    FAIL_REASON="expect missing or empty: $EXPECT"; echo blocked; return
  fi
  echo done
}

send_wake() {  # $1 status; never changes the outcome
  [ -n "$WAKE_URL" ] || return 0
  local exp="" body
  [ -n "$EXPECT" ] && exp="$RUN_DIR/$EXPECT"
  body="$(jq -nc --arg id "$ID" --arg status "$1" --arg run_dir "$RUN_DIR" --arg expect_path "$exp" \
    '{id:$id,status:$status,run_dir:$run_dir,expect_path:$expect_path}')"
  if ! curl -fsS -m 10 -X POST -H 'Content-Type: application/json' --data "$body" "$WAKE_URL" >/dev/null 2>>"$RUN_DIR/log"; then
    echo "runner: wake failed for $WAKE_URL" >>"$RUN_DIR/log"
  fi
}

finish() {  # $1 status
  local st="$1" rc
  echo "$st" > "$RUN_DIR/status"
  [ -n "$FAIL_REASON" ] && echo "$FAIL_REASON" > "$RUN_DIR/reason"
  send_wake "$st"
  case "$st" in
    done) rc=$EXIT_DONE ;; failed) rc=$EXIT_FAILED ;; blocked) rc=$EXIT_BLOCKED ;;
    partial) rc=$EXIT_PARTIAL ;; *) rc=$EXIT_USAGE ;;
  esac
  echo "runner: id=$ID status=$st run_dir=$RUN_DIR" >&2
  exit "$rc"
}
```

The `decide_status` output is captured with `$(...)`, which runs in a subshell, so `FAIL_REASON` set inside it is lost. To keep it, change `main` so it calls `decide_status` without command substitution:

```bash
main() {
  parse_args "$@"
  make_run_dir
  validate_after_dir
  run_engine
  local st; decide_status > "$RUN_DIR/.st"; st="$(cat "$RUN_DIR/.st")"; rm -f "$RUN_DIR/.st"
  [ "$st" = blocked ] && FAIL_REASON="expect missing or empty: $EXPECT"
  finish "$st"
}
```

- [ ] **Step 4: Run the full suite and confirm it passes:**

```bash
bash tests/runner_test.sh
```

Expected: `passed=19 failed=0`.

- [ ] **Step 5: Commit:**

```bash
git add bin/runner tests/runner_test.sh && git commit -m "feat(runner): --expect gate (blocked) and wake webhook"
```

---

## Task 5: Engine adapters — `shell` works, `grok` and `opencode` are stubs

**Files:** modify `bin/runner` (add `resolve_engine`, update `main`), create `engines/README.md`, and modify `tests/runner_test.sh`.

- [ ] **Step 1: Append failing tests above `run_tests`:**

```bash
test_grok_stub_is_usage() {
  "$RUNNER" --id g1 --engine grok --workdir "$WORK" -- "do a thing"; rc=$?
  assert_eq "$rc" 4
  assert_eq "$(cat "$RUNNER_RUNS_ROOT/g1/status")" usage
  assert_contains "$RUNNER_RUNS_ROOT/g1/reason" "not implemented"
}

test_opencode_stub_is_usage() {
  "$RUNNER" --id o1 --engine opencode --workdir "$WORK" -- "do a thing"; rc=$?
  assert_eq "$rc" 4
}

test_unknown_engine_is_usage() {
  "$RUNNER" --engine nope --workdir "$WORK" -- true; rc=$?
  assert_eq "$rc" 4
}
```

- [ ] **Step 2: Run the new tests and confirm they fail:**

```bash
bash tests/runner_test.sh 'stub'
```

Expected: both stub tests show `FAIL`, because the command runs as shell and either exits non-zero (`failed`, rc 1) or is not found.

- [ ] **Step 3: In `bin/runner`, add `resolve_engine` after `validate_after_dir` and update `main`:**

```bash
# Maps --engine to the argv that run_engine executes. v1: only shell is real.
resolve_engine() {
  case "$ENGINE" in
    shell) : ;;  # CMD runs as-is (e.g. bash -lc '...')
    grok|opencode)
      die_usage "engine '$ENGINE' not implemented in v1 (see engines/README.md); use --engine shell" ;;
  esac
}

main() {
  parse_args "$@"
  make_run_dir
  validate_after_dir
  resolve_engine
  run_engine
  local st; decide_status > "$RUN_DIR/.st"; st="$(cat "$RUN_DIR/.st")"; rm -f "$RUN_DIR/.st"
  [ "$st" = blocked ] && FAIL_REASON="expect missing or empty: $EXPECT"
  finish "$st"
}
```

- [ ] **Step 4: Write `engines/README.md`:**

```markdown
# Engine adapters

`runner --engine NAME -- ARGS...` resolves NAME to a command and supervises it.

Contract for every engine:
- cwd = `--workdir`; stdin = `/dev/null`; stdout+stderr appended to `$RUNNER_RUN_DIR/log`.
- Env: `RUNNER_RUN_DIR` (absolute run folder), `RUNNER_ID`.
- Write artifacts (for `--expect`) under `$RUNNER_RUN_DIR`, e.g. `$RUNNER_RUN_DIR/out.md`.
- Exit 0 on success. Any non-zero exit → status `failed`.
- Must emit log output or touch git in the workdir at least once per `--stall-minutes`.

| Engine | v1 | Notes |
|--------|----|-------|
| `shell` | shipped | Runs ARGS verbatim, e.g. `bash -lc '...'` |
| `grok` | stub (exit 4) | Future: wrap `grok` CLI headless, prompt from ARGS, write `out.md` |
| `opencode` | stub (exit 4) | Future: wrap `opencode run`, write `out.md` |

Policy layers (templates, push rules, allow-paths) are out of scope for this repo;
consumers such as Poly wrap `runner --engine shell -- their-script.sh`.
```

- [ ] **Step 5: Run the full suite:**

```bash
bash tests/runner_test.sh
```

Expected: `passed=22 failed=0`.

- [ ] **Step 6: Commit:**

```bash
git add bin/runner engines/README.md tests/runner_test.sh && git commit -m "feat(runner): engine dispatch; shell shipped, grok/opencode stubs"
```

---

## Task 6: Dockerfile, entrypoint, compose, .env.example

**Files:** rewrite the untracked private copies `Dockerfile`, `entrypoint.sh`, `compose.yaml`, and `.env.example`. Remove .NET, gh, opencode, grok, `MILL_*`, the second worker, the Poly `REPO_URL`, and pool mode. Pool mode is Enterprise-only and not part of the v1 success bar; add it later as an overlay if needed.

- [ ] **Step 1: Write `Dockerfile`:**

```dockerfile
# syntax=docker/dockerfile:1
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates jq python3 tini procps util-linux \
 && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 ships user "ubuntu" at uid 1000; replace it with "agent"
RUN userdel -r ubuntu 2>/dev/null || true; useradd -m -u 1000 -s /bin/bash agent \
 && mkdir -p /work && chown agent:agent /work

COPY --chmod=0755 bin/runner /usr/local/bin/runner
COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER agent
WORKDIR /home/agent
ENV PATH=/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin

# Cursor CLI -> ~/.local/bin/{agent,cursor-agent}. Skippable for CI self-test.
ARG INSTALL_CURSOR=1
RUN if [ "$INSTALL_CURSOR" = 1 ]; then curl -fsSL https://cursor.com/install | bash && ~/.local/bin/cursor-agent --version; fi

# Mount points for named volumes (pre-created so they're owned by agent)
RUN mkdir -p ~/.cursor ~/.config ~/.runner-runs /work

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["worker"]
```

- [ ] **Step 2: Write `entrypoint.sh`.** Machine mode only. The `start` form is the one already proven on a live CLI in the private copy:

```bash
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
```

- [ ] **Step 3: Write `compose.yaml`:**

```yaml
services:
  worker:
    build: .
    image: agent-host:latest
    hostname: ${WORKER_NAME:-agent-host-1}
    restart: unless-stopped
    init: false            # tini is PID 1
    stop_grace_period: 30s
    env_file:
      - path: .env
        required: false
    mem_limit: ${MEM_LIMIT:-4g}
    cpus: ${CPUS:-2}
    environment:
      WORKER_NAME: ${WORKER_NAME:-agent-host-1}
      REPO_URL: ${REPO_URL:-}
      MAX_AGENTS: ${MAX_AGENTS:-}
    volumes:
      - cursor:/home/agent/.cursor
      - config:/home/agent/.config        # cursor login state, git identity
      - runs:/home/agent/.runner-runs
      - work:/work
      # Optional read-only wake config, e.g. a file holding your webhook URL:
      # - ./wake:/home/agent/.wake:ro

volumes:
  cursor: {}
  config: {}
  runs: {}
  work: {}
```

- [ ] **Step 4: Write `.env.example`:**

```bash
# Copy to .env. No secrets required for machine mode.
WORKER_NAME=agent-host-1
# Optional: repo the worker serves; if unset an empty git repo is created at /work/repo
# REPO_URL=https://github.com/you/your-repo.git
# MAX_AGENTS=1
# WORKER_DEBUG_FILE=/work/worker.log
MEM_LIMIT=4g
CPUS=2
```

- [ ] **Step 5: Validate the compose file and build the image without the Cursor CLI** (faster, no network installer):

```bash
docker compose config -q && docker build --build-arg INSTALL_CURSOR=0 -t agent-host:test . && docker run --rm agent-host:test runner --help
```

Expected: `config` prints nothing, the build succeeds, and the help text starts with `usage: runner`.

- [ ] **Step 6: Build the full image** (installs the Cursor CLI):

```bash
docker compose build && docker compose run --rm worker cursor-agent --version
```

Expected: a version string is printed.

- [ ] **Step 7: Confirm no Poly references remain:**

```bash
grep -RniE 'poly|dotnet|mill|roslynk|opencode|grok' Dockerfile compose.yaml entrypoint.sh .env.example || echo clean
```

Expected: `clean`.

- [ ] **Step 8: Commit:**

```bash
git add Dockerfile entrypoint.sh compose.yaml .env.example && git commit -m "feat(docker): Poly-free worker image, machine-mode entrypoint, compose"
```

---

## Task 7: `examples/hello-job` and the README clone→job checklist

**Files:** create `examples/hello-job/prompt.md` and `examples/hello-job/README.md`; rewrite `README.md`.

- [ ] **Step 1: Write `examples/hello-job/prompt.md`.** This is pasted into the Cloud Agent:

````markdown
You are an orchestrator on a self-hosted agent-host machine. Do not edit files or interpret output.

Run exactly this command in the terminal, wait for it to exit, report its exit code, then stop:

```bash
runner --id hello-$(date +%s) --engine shell --timeout 5 --stall-minutes 2 --expect out.md -- \
  bash -lc 'echo "hello from $(hostname) at $(date -u +%FT%TZ)" > "$RUNNER_RUN_DIR/out.md"; cat "$RUNNER_RUN_DIR/out.md"'
```
````

- [ ] **Step 2: Write `examples/hello-job/README.md`:**

````markdown
# hello-job

Proves the success bar: one watchable job on your worker, finished in the Cursor UI.

1. Worker is up and listed under Cursor → Cloud Agents → Personal machines (see top-level README).
2. Start a Cloud Agent targeting that machine, with a cheap model (Auto is fine).
3. Paste `prompt.md` as the task.
4. Watch the session; it ends after `runner` exits 0.
5. Verify on the worker:

```bash
docker compose exec worker bash -lc 'd=$(ls -td ~/.runner-runs/hello-* | head -1); cat "$d/status" "$d/out.md"'
```

Expected: `done` then `hello from <hostname> at <time>`.
````

- [ ] **Step 3: Rewrite `README.md`:**

````markdown
# agent-host

Run a Cursor self-hosted worker in Docker, plus `runner`: a tiny supervisor for one durable job.
A cheap Cursor Cloud Agent orchestrates (invokes `runner`, then exits); `runner` handles
timeout, stall, status, artifacts, and an optional wake webhook.

## Quickstart (clone → job)

- [ ] `git clone https://github.com/scoizzle/agent-host && cd agent-host`
- [ ] `cp .env.example .env` and set `WORKER_NAME`
- [ ] `docker compose build`
- [ ] Log in once (state persists in the `config`/`cursor` volumes):
      `docker compose run --rm worker cursor-agent login`
- [ ] `docker compose up -d && docker compose logs -f worker`
- [ ] In Cursor, the machine `WORKER_NAME` appears under Personal machines
- [ ] Run [`examples/hello-job`](examples/hello-job/README.md); the session finishes and
      `~/.runner-runs/<id>/status` reads `done`

Stop cleanly: `docker compose down` (SIGTERM → worker disconnects).

## runner reference

```text
runner [--id NAME] [--engine shell|grok|opencode]
       [--workdir PATH] [--timeout MIN] [--stall-minutes N]
       [--expect RELPATH] [--wake-url URL] -- <command...>
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--id` | `YYYYmmdd-HHMMSS-xxxx` | Run folder `~/.runner-runs/<id>/` (must not exist) |
| `--engine` | `shell` | `shell` runs the command; `grok`/`opencode` are v1 stubs (exit 4) |
| `--workdir` | `/work/repo` | cwd for the engine |
| `--timeout` | 0 (off) | Minutes before kill → `failed` |
| `--stall-minutes` | 0 (off) | Minutes with no log write and no git change → kill → `failed` |
| `--expect` | none | File relative to the run folder that must be non-empty, else `blocked` |
| `--wake-url` | none | POST `{id,status,run_dir,expect_path}` JSON on finish |

Engine env: `RUNNER_RUN_DIR`, `RUNNER_ID`. Run folder: `status`, `reason`, `log`, `out.md`, `cmd`, `pid`.

| Status | Exit |
|--------|------|
| `done` | 0 |
| `failed` (engine error, timeout, stall) | 1 |
| `blocked` (expect missing/empty) | 2 |
| `partial` (reserved) | 3 |
| `usage` | 4 |

## Development

`bash tests/runner_test.sh` (unit) · `bash tests/docker_selftest.sh` (needs Docker).

Out of scope: project-specific policy (templates, PR push, allow-paths). Wrap `runner` from your own repo.

License: MIT.
````

- [ ] **Step 4: Check that every flag in the README matches the parser:**

```bash
for f in id engine workdir timeout stall-minutes expect wake-url; do grep -q -- "--$f)" bin/runner || echo "missing $f"; done; echo checked
```

Expected: `checked` with no `missing` lines.

- [ ] **Step 5: Commit:**

```bash
git add README.md examples/ && git commit -m "docs: README quickstart and hello-job example"
```

---

## Task 8: CI — shellcheck, unit tests, Docker self-test

**Files:** create `tests/docker_selftest.sh`; replace `.github/workflows/ci.yml`.

- [ ] **Step 1: Write `tests/docker_selftest.sh`.** It runs the real runner inside the image with no Cursor login:

```bash
#!/usr/bin/env bash
# Build the image (without Cursor CLI) and prove runner works in-container.
set -euo pipefail
cd "$(dirname "$0")/.."
IMG=agent-host:selftest
docker build --build-arg INSTALL_CURSOR=0 -t "$IMG" .

run() { docker run --rm "$IMG" bash -lc "$1"; }

# done path
run 'mkdir -p /work/repo && runner --id ok --expect out.md -- bash -c "echo hi > \"\$RUNNER_RUN_DIR/out.md\"" && test "$(cat ~/.runner-runs/ok/status)" = done'
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
[ "$(docker run --rm "$IMG" id -un)" = agent ] && echo "selftest: user ok"
echo "selftest: PASS"
```

- [ ] **Step 2: Run the self-test locally:**

```bash
chmod +x tests/docker_selftest.sh && bash tests/docker_selftest.sh
```

Expected: the build completes and the final line reads `selftest: PASS`.

- [ ] **Step 3: Replace `.github/workflows/ci.yml`:**

```yaml
name: ci
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y shellcheck
      - run: shellcheck -x bin/runner entrypoint.sh tests/*.sh
  unit:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - run: bash tests/runner_test.sh
  docker:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - run: docker compose config -q
      - run: bash tests/docker_selftest.sh
```

- [ ] **Step 4: Run shellcheck locally and fix all findings inline:**

```bash
shellcheck -x bin/runner entrypoint.sh tests/*.sh && echo lint-ok
```

Expected: `lint-ok`. These findings are intentional and can be silenced with a disable comment on the line:
- SC2317 on the `trap` handler: add `# shellcheck disable=SC2317`.
- SC2034 on unused `EXIT_*` constants: add `# shellcheck disable=SC2034`.

- [ ] **Step 5: Commit:**

```bash
git add tests/docker_selftest.sh .github/workflows/ci.yml bin/runner entrypoint.sh tests/ && git commit -m "ci: shellcheck, unit tests, docker runner self-test"
```

---

## Task 9: Publish and manual smoke (human-gated)

- [ ] **Step 1: Confirm the tree is clean and complete:**

```bash
git status --short && git ls-files
```

Expected: no untracked Poly files; the tracked files match the File Structure table.

- [ ] **Step 2: Get Scot's explicit approval, then create the public repo and push.** Do not push without approval, because the repo is public. Command after approval:

```bash
gh repo create scoizzle/agent-host --public --source . --push
```

- [ ] **Step 3: Confirm CI is green on GitHub** (`lint`, `unit`, `docker`).

- [ ] **Step 4: Manual compose smoke (Scot, once).** On a Docker host, follow the README Quickstart through `docker compose up -d`. Expected: the machine appears under Cursor Personal machines.

- [ ] **Step 5: Manual hello job (Scot, once).** Follow `examples/hello-job/README.md`. Expected: the session ends, `status` reads `done`, and `out.md` is non-empty.

- [ ] **Step 6: Clean SIGTERM check:**

```bash
docker compose down
```

Expected: the command returns in under 30 seconds and the logs show the worker disconnecting rather than being killed with SIGKILL.

---

## Spec coverage self-review

| Spec item | Task |
|-----------|------|
| §1 worker registers via `cursor-agent worker start`, machine mode, single identity in container | 6 |
| §2 Dockerfile + compose, caps, named volumes, optional RO wake bind | 6 |
| §2 entrypoint clean SIGTERM | 6, 9.6 |
| §2 runner, engine adapters, hello-job, README | 2–5, 7 |
| §3 run dir with `status=running`, empty `out.md`/`log` | 2 |
| §3 cwd = `--workdir` default `/work/repo` | 2 |
| §3 watch: exit / timeout / stall (log + git idle), kill process group | 3 |
| §3 expect missing/empty → blocked | 4 |
| §3 final status + wake POST + exit mapping | 2, 4 |
| §4 flags, `RUNNER_RUN_DIR`/`RUNNER_ID`, exit codes 0–4, wake JSON `{id,status,run_dir,expect_path}` | 2–5 |
| §4 grok/opencode stubs exit usage | 5 |
| §5 unit (no Docker), Docker-in-CI self-test, no CloudAgent in CI | 2–5, 8 |
| §5 compose smoke + hello job manual checklist | 7, 9 |
| §5 stall/timeout fixtures + process group dead | 3 |
| §5 wake test with local listener | 4 (python http.server in place of nc/httpbin) |
| §6 non-goals: no Poly, no pool/SaaS | Global Constraints, 1, 6.7 |
| MIT license | 1 |

Decisions made while planning (flag these to Scot if he disagrees):
- **Prompt and stdin capture is dropped from v1.** The engine's stdin is `/dev/null`, so a Cloud Agent shell can never block on it, and no `prompt.md` is written. Prompts travel in the command args. The spec says "as needed", so this fits.
- **Pool mode is removed from the entrypoint.** It needs Enterprise and is not part of the success bar.
- **The wake call is best-effort.** If the POST fails, the job's status does not change; the failure is written to `log`.
- **Minute-scaling and runs-root env hooks exist only so tests run fast.** They are documented in Global Constraints.
- **`partial` is reserved.** The exit-code map includes it, but no v1 code path produces it.
