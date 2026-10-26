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
