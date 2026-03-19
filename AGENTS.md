# Repo Guide

This repo stores an AI agent skill for querying Grafana Loki logs via the `grafana/logcli` Docker image.

Installed global skill directory: `~/.agents/skills/logcli`.

## Where to start

- Read this file, then `SKILL.md` for the full command list and usage.
- Run all commands via `scripts/logcli.sh` from the repo root.

## Goal

- Keep the CLI a thin, dependency-light wrapper around grafana/logcli.
- Preserve JSON error contract and stable CLI flags.
- Keep environment-specific logic (URLs, chunk sizes) configurable, not hardcoded.

## Source of truth

- `SKILL.md` for the public command contract.
- `references/logql-cheatsheet.md` for LogQL syntax.
- `grafana/logcli --help` for upstream flag reference.

## Repo layout

- **SKILL.md** — skill contract and usage instructions for agents.
- **README.md** — public project overview and installation.
- **scripts/logcli.sh** — single CLI entrypoint (dispatcher).
- **scripts/_lib/common.sh** — shared helpers: .env loading, env resolution, chunking, JSON output.
- **references/logql-cheatsheet.md** — LogQL syntax and common query patterns.
- **tests/** — automated validation scripts.
- **.env** — credentials file (git-ignored, never committed).

## Working rules

- The CLI must work with bash 4.0+ and standard unix tools (`jq`, `date`, `docker`).
- No Python or other runtime dependencies.
- Preserve CLI behavior. Existing commands, arguments, and output shapes must remain stable.
- Preserve JSON error output as the integration boundary.
- If you change script behavior, update both `SKILL.md` and `README.md`.
- Never commit `.env` or Loki URLs that contain auth tokens.
- Keep `references/logql-cheatsheet.md` in sync when adding new commands.

## Validation

- After changes: `make compile` then `make test`.
- `make compile` runs shellcheck on all `.sh` files.
- `make test` runs unit tests (no Docker required).
- `make test-live` runs live integration tests (requires Docker and network access).
- `make check` verifies prerequisites (docker, jq, bash, shellcheck).

## Common pitfalls

- Docker must be running for any actual Loki queries.
- The `grafana/logcli:latest` image must be pulled before first use.
- Chunk sizes differ per environment; never exceed them in a single query window.
- macOS `date` and GNU `date` have different flags for RFC3339 parsing — `common.sh` handles both.
- Bash 3.x (macOS default) does not support associative arrays; require bash 4.0+ (available via `brew install bash`).

## Deviations from skill-requirements.md

- Uses a single `scripts/logcli.sh` entrypoint instead of `scripts/commands/<entity>/<action>.sh` because the skill wraps one external tool with 4 subcommands, not a multi-entity CRUD surface.
- No `scripts/applescripts/` directory (not a macOS app skill).
- Follows the same single-entrypoint pattern as `plex-skill/scripts/plex_cli.py`.
