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
