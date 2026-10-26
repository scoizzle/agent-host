# agent-host OSS v1 — Design

**Date:** 2026-10-26  
**Status:** Draft for review (sections §1–§6 approved in chat; defaults locked below)  
**Owner:** Scot Murphy / Chieftan  
**Approach:** B — one OSS repo with Docker worker image + compose, plus a Poly-free general `runner` CLI in the same repo. Poly is a consumer that mounts mill templates/policy on top, not in the OSS core.

## Goal

Productize the durable-worker + cheap-orchestrator pattern so anyone can:

1. Clone the repo  
2. Bring up a Cursor self-hosted worker (Docker)  
3. Run one monitorable job  
4. See that job finish in the Cursor Cloud Agent UI  

**Success bar:** clone → worker up → one watchable job, with **no Poly** required.

**Product surface:** Cursor Cloud Agent on a self-hosted worker is required for v1. Real engines may be shell (v1), later grok/opencode; the Cloud Agent is a thin orchestrator that only invokes `runner`.

## Locked defaults (from §6)

| Decision | Choice |
|----------|--------|
| Repo home | New public repo `scoizzle/agent-host` (copy Dockerfile/compose/runner from today’s private agent-host) |
| Runner language | Bash v1 (mill.sh stripped); Go later if unit tests hurt |
| Stall/timeout status | Map to `failed`; reason in status file / log |
| `--expect` root | Path relative to the **run folder** (`~/.runner-runs/<id>/`) |
| License | MIT |

---

## §1 Architecture

```
┌─────────────────────┐         ┌──────────────────────────────────┐
│ Cursor Cloud Agent  │  SSH /  │ Docker worker (Personal machine) │
│ (cheap model: Auto /│  agent  │  cursor-agent worker start         │
│  gpt-5.4-nano)      │ ──────► │  /usr/local/bin/runner             │
│ orchestrates only   │         │  ~/.runner-runs/<id>/              │
└─────────────────────┘         │  /work/repo (workdir)              │
                                └──────────────────────────────────┘
```

- **Orchestrator** = Cursor Cloud Agent session targeting the registered worker machine. It chooses engine + args, sets workdir, runs `runner`, exits. It does not interpret job output.
- **Worker** = container that registers as a Cursor Personal machine (`cursor-agent worker start`). One identity in-container (no Mac-host hop / `docker exec` for jobs).
- **Runner** = durable job supervisor: timeout, stall, status file, optional `--expect`, optional wake webhook, exit codes.
- **Engines** = adapters behind `runner --engine …`. v1 ships `shell` for the success bar; `grok` / `opencode` are stubs or thin wrappers without Poly policy.

Done signal for operators: Cloud Agent session completion (immediate). Optional mill-style wake webhook carries status/`out.md` detail when configured.

---

## §2 Components (what ships in the repo)

| Piece | Responsibility |
|-------|----------------|
| `Dockerfile` + `compose.yaml` | Build/run the worker; CPU/mem caps; named volumes for logins + `/work`; optional RO wake bind |
| Entrypoint | `cursor-agent worker start` in machine mode; clean SIGTERM disconnect |
| `runner` CLI | One job: timeout, stall-on-log/git-idle, status file, `--expect`, optional wake webhook, run folder, exit codes |
| Engine adapters | v1: **`shell`** (required). Stubs/docs for `grok` / `opencode`. Poly mill policy stays out-of-tree |
| `examples/hello-job/` | Prompt + orchestrator snippet: cheap CloudAgent runs `runner --engine shell --expect out.md -- …` |
| `README.md` | Clone → login once → `compose up` → appear in Cursor Personal machines → launch example → watch done |

**Out of OSS v1 core:** Poly templates, opposite-mill rules, PR push / allow-path policy, Roslynk / .NET heap knobs (Poly fork or optional compose overlays).

---

## §3 Job lifecycle (runner contract)

1. **Create** — `runner` makes `/home/agent/.runner-runs/<id>/` with `status=running`, prompt/stdin capture as needed, empty `out.md` / `log`.
2. **Start engine** — adapter launches the engine (`shell` = command after `--`) with cwd = `--workdir` (default `/work/repo`).
3. **Watch** — until process exit, `--timeout`, or stall (no log / no git change for `--stall-minutes`). Kill the process group on stall/timeout.
4. **Expect** — if `--expect RELPATH` and file missing/empty under the **run folder** → status **`blocked`** (not `partial`).
5. **Status + wake** — write final status (`done` \| `failed` \| `blocked` \| `partial` \| `usage`); optional POST to `--wake-url`; exit with mapped code.
6. **Orchestrator** — cheap CloudAgent only invokes `runner` and stops. Cursor UI shows session done when the agent exits.

No push, no allow-path, no opposite-mill in core.

### Status meanings

| Status | When |
|--------|------|
| `running` | Job started |
| `done` | Engine exited 0 and `--expect` (if any) is non-empty |
| `failed` | Engine non-zero, stall, or timeout (reason recorded in log / status sidecar) |
| `blocked` | `--expect` missing/empty after engine finish (or equivalent gate) |
| `partial` | Reserved for future “engine ok but soft gates”; **not** used for missing expect in v1 |
| `usage` | Bad flags / unsupported engine |

---

## §4 CLI surface

```text
runner [--id NAME] [--engine shell|grok|opencode]
       [--workdir PATH] [--timeout MIN] [--stall-minutes N]
       [--expect RELPATH] [--wake-url URL]
       -- <engine args / command>
```

| Flag | Behavior |
|------|----------|
| `--id` | Run folder name under `~/.runner-runs/`; default = timestamp slug |
| `--engine shell` | Required for v1 success bar; after `--`, command runs in `--workdir` |
| `--workdir` | Default `/work/repo` |
| `--expect` | Path **relative to the run folder**; engines must write artifacts there (e.g. `out.md`) |
| `--wake-url` | Optional POST on terminal status; JSON body `{id,status,run_dir,expect_path}`; auth is caller’s (query/header secret) |
| `--timeout` / `--stall-minutes` | Hard stop; map to `failed` with reason |

**Env exported to the engine:** `RUNNER_RUN_DIR` = absolute path of the run folder; `RUNNER_ID` = run id. Shell/hello-job examples write `--expect` artifacts via `$RUNNER_RUN_DIR/…`.

**Exit codes:** `0` done, `1` failed, `2` blocked, `3` partial, `4` usage/bad flags.

**Example orchestrator prompt:** On this machine, run `runner --engine shell --expect out.md -- bash -lc 'echo hello > "$RUNNER_RUN_DIR/out.md"'` (or equivalent documented env), then exit. CloudAgent does not parse `out.md`.

Grok/opencode adapters in v1: documented stubs that exit `usage` until implemented (or thin wrappers stripped of Poly policy).

---

## §5 Verification

| Gate | What | Pass means |
|------|------|------------|
| Unit | Flag parse, exit codes, status file write, expect missing → blocked | CI without Docker |
| Compose smoke | `compose up` → worker registers as Cursor Personal machine | Machine appears in Cursor UI (manual once per env) |
| Hello job | CloudAgent on that machine with `examples/hello-job` | Session ends; `~/.runner-runs/<id>/status=done` and `out.md` non-empty |
| Stall/timeout | Fixture that sleeps / goes silent | status `failed`; process group dead |
| Wake (optional) | local httpbin / `nc` | POST with id + status |

**CI:** unit + Docker-in-CI runner self-test. **No CloudAgent in CI** (Cursor login is out of band). README human checklist: compose smoke + hello job once.

Poly mill regression / allow-path / opposite-mill stay in Poly overlays — not this suite.

---

## §6 Non-goals

- Poly templates, opposite-mill, allow-path, PR push, Roslynk, .NET-specific image knobs in core  
- Multi-tenant SaaS control plane  
- Non-Cursor job UI for v1  
- Free-model / Poly mill policy inside OSS runner  

### Poly relationship

Poly remains a **consumer**: same worker image pattern, mill.sh (or a Poly adapter) mounts templates and policy on top of `runner`. agent-host OSS must stay useful without Poly installed.

---

## Implementation notes (for the later plan — not approved work yet)

1. Create public `scoizzle/agent-host` (MIT).  
2. Copy/adapt private Dockerfile, compose, entrypoint; strip Poly-only bits.  
3. Extract `runner` from mill.sh: keep timeout/stall/status/expect/wake; drop allow-path, opposite-mill, PR push, Poly templates.  
4. Ship `shell` engine + hello-job example + README.  
5. Stub grok/opencode engines.  
6. Unit tests + Docker self-test in CI.  
7. Manual smoke: register worker, run hello CloudAgent.  

**Out of scope until a follow-on plan:** migrating Scot’s live Poly mills onto OSS `runner`, launch-SHA allowlist fix (tracked separately in Poly), Go rewrite.

---

## Open follow-ups (explicitly deferred)

- Whether Poly’s `mill.sh` becomes a thin wrapper calling `runner` or stays a fork  
- Exact wake payload compatibility with existing Grok Bot mill-wake routine  
- Multi-job concurrency limits on one worker  

---

## Approval record

- Approach B chosen (2026-10-26)  
- §1 Architecture OK  
- §2 Components OK  
- §3 Job lifecycle OK (missing expect → `blocked`)  
- §4 CLI surface OK  
- §5 Verification OK  
- §6 Non-goals OK; defaults accepted (new public repo, bash, failed-for-stall, expect under run folder, MIT)
