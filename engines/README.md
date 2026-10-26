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
