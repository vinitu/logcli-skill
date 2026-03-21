# Repo Guide

This repo stores an AI agent skill for querying Grafana Loki logs.
Installed global skill directory: `~/.agents/skills/logcli`.
Package source: `vinitu/logcli-skill`.

## Where to start

- Read this file, then `SKILL.md` for the full command list and usage.
- Run public commands from the repo root via `scripts/commands/logs/*.sh`.
- `scripts/logcli.sh` is a compatibility wrapper for older automation. Prefer `scripts/commands/logs/*.sh`.

## Goal

- Keep the CLI a thin, dependency-light wrapper around `logcli`.
- Keep the public `scripts/commands/logs` contract stable.
- Preserve JSON error contract and stable flags.
- Prefer local `logcli` when available and use Docker only as fallback.
- Keep environment-specific logic (URLs, chunk sizes, backend selection) configurable, not hardcoded.

## Source of truth

- `SKILL.md` for the public command contract and JSON output rules.
- `README.md` for install, package naming, repo layout, and known limits.
- `references/logql-cheatsheet.md` for LogQL syntax.

## Repo layout

- **SKILL.md** — skill contract and usage instructions for agents.
- **README.md** — public repo overview, install source, and validation flow.
- **scripts/commands/logs/** — public shell interface. Run these commands from the repo root.
- **scripts/logcli.sh** — compatibility dispatcher that forwards to `scripts/commands/logs/*.sh`.
- **scripts/_lib/common.sh** — internal shared helpers for env resolution, chunking, backend resolution, and JSON helpers.
- **references/logql-cheatsheet.md** — LogQL syntax and common query patterns.
- **tests/** — automated contract and help checks.
- **.env** — credentials file (git-ignored, never committed).

## Working rules

- The CLI must work with bash 4.0+ and standard unix tools (`jq`, `date`).
- No Python or other runtime dependencies.
- Public commands live only in `scripts/commands/logs/*.sh`.
- Keep `scripts/_lib` internal. Do not document it as public API.
- Preserve command behaviour, arguments, and output shapes unless a breaking change is approved.
- Preserve JSON error output as the integration boundary for automation.
- Prefer local `logcli` from `PATH` or `LOGCLI_BIN`. Use Docker only when local `logcli` is not available.
- The shell wrappers must not read `.env` themselves. The agent should find the needed Loki URL and pass it as `LOKI_URL` directly with the command.
- The agent should not manually verify which backend is available. The shell wrappers handle that.
- If you change script behavior, update both `SKILL.md` and `README.md`.
- Never commit `.env` or Loki URLs that contain auth tokens.
- Keep `references/logql-cheatsheet.md` in sync when adding new commands.

## Validation

- After changes: `make compile` then `make test`.
- `make compile` runs shellcheck on all `.sh` files.
- `make test` runs unit tests (no Docker required).
- `make test-live` runs live integration tests (requires Docker and network access).
- `make check` verifies prerequisites (`logcli` or Docker, jq, bash, shellcheck).

## Public vs internal

- Public: `scripts/commands/logs/query.sh`, `labels.sh`, `label-values.sh`, `series.sh`
- Compatibility: `scripts/logcli.sh`
- Internal: `scripts/_lib/common.sh`

## Safety rules

- All commands are read-only. No write operation exists.
- Treat Loki data as real user data. Do not store logs or copy secrets into docs or tests.
- Keep `.env` local and untracked.

## Common pitfalls

- Local `logcli` takes priority over Docker.
- If local `logcli` is missing, Docker must be running for Loki queries.
- The fallback image is `grafana/logcli:latest` unless `LOGCLI_IMAGE` overrides it.
- Chunk sizes differ per environment; never exceed them in a single query window.
- macOS `date` and GNU `date` have different flags for RFC3339 parsing — `common.sh` handles both.
- Bash 3.x (macOS default) does not support associative arrays; require bash 4.0+ (available via `brew install bash`).
- No `scripts/applescripts/` directory exists because this skill wraps Docker, not a macOS app.
- All tests live in top-level `tests/`.
