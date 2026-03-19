---
name: logcli
description: Query Loki logs using grafana/logcli via Docker. Use when you need to search logs, list labels, or inspect log series from a Grafana Loki instance.
---

# Loki LogCLI Skill

Use this skill when the task is about querying Grafana Loki logs.

## Overview

- Public interface: `scripts/logcli.sh`
- Backend: `docker run grafana/logcli:latest`
- Output: JSON status envelopes + raw log lines
- Auto-chunks time ranges that exceed environment limits

## Main Rule

Use only `scripts/logcli.sh`.
Do not call `docker run grafana/logcli` directly — the script handles environment resolution, auto-chunking, and error reporting.

## Requirements

- Docker (with `grafana/logcli:latest` image)
- `bash` 4.0+ (`brew install bash` on macOS)
- `jq` (optional, for JSON array formatting)

## Quick Start

```bash
# 1. Create .env from example
cp ~/.agents/skills/logcli/.env.example ~/.agents/skills/logcli/.env

# 2. Set environment
echo 'LOKI_ENV=dev' > ~/.agents/skills/logcli/.env

# 3. Test connectivity
~/.agents/skills/logcli/scripts/logcli.sh labels --since 1h
```

## Commands

### query

Run a LogQL query with auto-chunking.

```bash
scripts/logcli.sh query '{job="app"}' --since 1h
scripts/logcli.sh query '{job="app", level="error"}' --since 30m --env prod
scripts/logcli.sh query '{job="app"}' --from 2026-03-18T06:00:00Z --to 2026-03-18T08:00:00Z
scripts/logcli.sh query '{job="app"}' --since 1h --output raw
scripts/logcli.sh query '{job="app"}' --since 1h --limit 1000
```

Flags:
- `--since <dur>` — relative time range: `5m`, `1h`, `6h` (default: `1h`)
- `--from <rfc3339>` — absolute start time
- `--to <rfc3339>` — absolute end time
- `--limit <n>` — max lines per chunk (default: `5000`)
- `--output <mode>` — logcli output mode: `raw`, `jsonl`, `default` (default: `jsonl`)
- `--env <name>` — environment: `dev`, `rc`, `prod` (default: `dev`)
- `--url <url>` — direct Loki URL (overrides `--env`)

Output: log lines to stdout, JSON status to stderr.

### labels

List available label names.

```bash
scripts/logcli.sh labels --since 1h
scripts/logcli.sh labels --since 1h --env prod
```

Output: `{"success":true,"env":"dev","command":"labels","results":["label1","label2"]}`

### label-values

List values for a specific label.

```bash
scripts/logcli.sh label-values job --since 1h
scripts/logcli.sh label-values type --since 1h --env rc
```

Output: `{"success":true,"env":"dev","command":"label-values","label":"job","results":["app","nginx"]}`

### series

List log series matching a selector.

```bash
scripts/logcli.sh series '{job="app"}' --since 1h
scripts/logcli.sh series '{job="nginx"}' --since 30m --env prod
```

Output: `{"success":true,"env":"dev","command":"series","selector":"{job=\"app\"}","results":[...]}`

## Environment Configuration

| Environment | Loki URL | Chunk Limit |
|-------------|----------|-------------|
| **dev** (default) | `https://loki-dev.example.invalid` | 6h |
| **rc** | `https://loki-rc.example.invalid` | 1h |
| **prod** | `https://loki-prod.example.invalid` | 5m |

Config resolution order: CLI flags → environment variables → `.env` file.
Real endpoints should come from `LOKI_URL`, `LOKI_URL_DEV`, `LOKI_URL_RC`, or `LOKI_URL_PROD`.

For custom Loki instances:
```bash
scripts/logcli.sh labels --url https://my-loki:3100 --since 1h
```

## Time Ranges and Auto-Chunking

Each environment has a max query window. If your time range exceeds it, the script automatically splits into sequential chunks.

Example: querying 3 hours on RC (1h chunk limit) runs 3 sequential queries.

Chunk limits: dev=6h, rc=1h, prod=5m.

## Output Contract

### query command
- **stdout**: raw log lines from logcli (for piping/grepping)
- **stderr**: JSON status: `{"success":true,"env":"dev","query":"...","chunks":1,"chunk_limit":"6h"}`

### labels, label-values, series commands
- **stdout**: JSON envelope: `{"success":true,"env":"...","command":"...","results":[...]}`

### errors (all commands)
- **stderr**: `{"success":false,"error":"descriptive message"}`
- Exit code: non-zero

## Safety Boundaries

- All operations are read-only (Loki queries only).
- No write operations exist.
- No query results are cached or stored.
- Loki URLs are in `.env`, never committed to git.

## References

- `references/logql-cheatsheet.md` for LogQL syntax and common patterns
- [LogQL documentation](https://grafana.com/docs/loki/latest/query/)
