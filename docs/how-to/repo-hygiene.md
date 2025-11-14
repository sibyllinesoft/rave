# Repo Hygiene Checklist

Keep the repository free of oversized binaries and transient artifacts to prevent AI agents and humans from tripping over noise.

## When to Run
- Before opening a pull request
- After touching VM images, `gitlab-complete/`, or other stateful directories
- Any time `git status` looks suspicious

## Command
```bash
scripts/repo/hygiene-check.sh
```

## What It Does
1. Flags any tracked file larger than 50 MiB (override via `HYG_CHECK_THRESHOLD`).
2. Reports tracked artifacts that should live outside Git (QCOW images, GitLab volumes, Redis/Postgres dumps, `run/` logs).
3. Warns about QCOW images anywhere outside `artifacts/`.
4. Lists untracked directories that are not ignored so you can decide whether to commit or clean them.

## Follow‑up Actions
- Move flagged binaries into `artifacts/` (ignored) or publish them as release assets.
- Keep per-profile qcow symlinks under `artifacts/qcow/<profile>/` and store stamped images in `artifacts/qcow/releases/` so the CLI can find them.
- Update `.gitignore` if a new scratch directory is meant to stay local.
- If a file must remain tracked, document the reason in `docs/refactor/notes.md` so future hygiene passes know it is intentional.
