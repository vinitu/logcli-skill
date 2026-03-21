---
name: logcli
description: Query Loki logs using local logcli when available, with grafana/logcli Docker fallback. Use when you need to search logs, list labels, or inspect log series from a Grafana Loki instance.
---

# Loki LogCLI Skill

Use this skill when the task is about querying Grafana Loki logs.

## Overview

- Public interface: `scripts/commands/logs/*.sh`
- Compatibility wrapper: `scripts/logcli.sh`
- Internal helpers: `scripts/_lib/common.sh`
- Runtime: local `logcli` first, Docker fallback second
- Output: JSON by default, with streamed logs for `query.sh`

## Main Rule

Use only `scripts/commands/logs/*.sh`.
Do not call `scripts/_lib/common.sh` or backend commands directly.

## Requirements

- Explicit `LOKI_URL` value passed to the command
- `bash` 4.0+ (`brew install bash` on macOS)
- `jq` (optional, for JSON array formatting)

The runtime chooses local `logcli` first and Docker second. The agent does not need to check that manually.

## Quick Start

```bash
LOKI_URL=https://loki.example.com \
~/.agents/skills/logcli/scripts/commands/logs/labels.sh --since 1h

LOKI_URL=https://loki.example.com \
~/.agents/skills/logcli/scripts/commands/logs/query.sh '{job="app"}' --since 1h
```

## Public Interface

- `scripts/commands/logs/query.sh`
- `scripts/commands/logs/labels.sh`
- `scripts/commands/logs/label-values.sh`
- `scripts/commands/logs/series.sh`

`scripts/logcli.sh` is a compatibility wrapper for older automation. Prefer the public commands above in new work.

## Output Rules

- `query.sh` writes log lines to stdout and a JSON status envelope to stderr.
- `labels.sh`, `label-values.sh`, and `series.sh` write JSON to stdout.
- Success output includes `backend`, which shows which runtime handled the command.
- Failures write JSON to stderr and return a non-zero exit code.

## Commands

### query

Run a LogQL query with auto-chunking.

```bash
LOKI_URL=https://loki.example.com \
scripts/commands/logs/query.sh '{job="app"}' --since 1h
scripts/commands/logs/query.sh '{job="app", level="error"}' --since 30m --url https://loki.example.com
LOKI_URL=https://loki.example.com \
scripts/commands/logs/query.sh '{job="app"}' --from 2026-03-18T06:00:00Z --to 2026-03-18T08:00:00Z
LOKI_URL=https://loki.example.com \
scripts/commands/logs/query.sh '{job="app"}' --since 1h --output raw
LOKI_URL=https://loki.example.com \
scripts/commands/logs/query.sh '{job="app"}' --since 1h --limit 1000
```

Flags:
- `--since <dur>` — relative time range: `5m`, `1h`, `6h` (default: `1h`)
- `--from <rfc3339>` — absolute start time
- `--to <rfc3339>` — absolute end time
- `--limit <n>` — max lines per chunk (default: `5000`)
- `--output <mode>` — logcli output mode: `raw`, `jsonl`, `default` (default: `jsonl`)
- `--url <url>` — direct Loki URL (overrides `LOKI_URL`)

Output: log lines to stdout, JSON status to stderr.

### labels

List available label names.

```bash
LOKI_URL=https://loki.example.com \
scripts/commands/logs/labels.sh --since 1h
scripts/commands/logs/labels.sh --since 1h --url https://loki.example.com
```

Output: `{"success":true,"command":"labels","backend":"local","results":["label1","label2"]}`

### label-values

List values for a specific label.

```bash
LOKI_URL=https://loki.example.com \
scripts/commands/logs/label-values.sh job --since 1h
scripts/commands/logs/label-values.sh type --since 1h --url https://loki.example.com
```

Output: `{"success":true,"command":"label-values","backend":"local","label":"job","results":["app","nginx"]}`

### series

List log series matching a selector.

```bash
LOKI_URL=https://loki.example.com \
scripts/commands/logs/series.sh '{job="app"}' --since 1h
scripts/commands/logs/series.sh '{job="nginx"}' --since 30m --url https://loki.example.com
```

Output: `{"success":true,"command":"series","backend":"local","selector":"{job=\"app\"}","results":[...]}`

## Environment Configuration

Config resolution order: CLI flags → explicit `LOKI_URL` environment variable.
Backend resolution order: `LOGCLI_BIN` → `logcli` from `PATH` → Docker fallback.
Chunk limits can come from `LOKI_CHUNK_SECONDS`.
The shell wrappers do not read `.env` by themselves. The agent should find the needed Loki URL and pass it as `LOKI_URL` together with the command.

For custom Loki instances:
```bash
scripts/commands/logs/labels.sh --url https://my-loki:3100 --since 1h
```

Example values:
```bash
LOKI_URL=https://loki.example.com
LOKI_CHUNK_SECONDS=3600
```

## Time Ranges and Auto-Chunking

Each environment has a max query window. If your time range exceeds it, the script automatically splits into sequential chunks.

Example: querying 3 hours with `LOKI_CHUNK_SECONDS=3600` runs 3 sequential queries.

## Output Contract

### query command
- **stdout**: raw log lines from logcli (for piping/grepping)
- **stderr**: JSON status: `{"success":true,"query":"...","chunks":1,"chunk_limit":"1h","backend":"local"}`

### labels, label-values, series commands
- **stdout**: JSON envelope: `{"success":true,"command":"...","backend":"local","results":[...]}`

### errors (all commands)
- **stderr**: `{"success":false,"error":"descriptive message"}`
- Exit code: non-zero

## Safety Boundaries

- All operations are read-only (Loki queries only).
- No write operations exist.
- No query results are cached or stored.
- Loki URLs should be passed as env vars, not hardcoded into commands.
- `scripts/_lib/common.sh` is internal and not part of the public contract.
- If local `logcli` is missing, Docker is the only supported fallback.

## References

- `references/logql-cheatsheet.md` for LogQL syntax and common patterns
- [LogQL documentation](https://grafana.com/docs/loki/latest/query/)
