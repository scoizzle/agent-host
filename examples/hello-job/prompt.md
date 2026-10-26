You are an orchestrator on a self-hosted agent-host machine. Do not edit files or interpret output.

Run exactly this command in the terminal, wait for it to exit, report its exit code, then stop:

```bash
runner --id hello-$(date +%s) --engine shell --timeout 5 --stall-minutes 2 --expect out.md -- \
  bash -lc 'echo "hello from $(hostname) at $(date -u +%FT%TZ)" > "$RUNNER_RUN_DIR/out.md"; cat "$RUNNER_RUN_DIR/out.md"'
```
