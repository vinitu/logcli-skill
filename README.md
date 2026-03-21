# logcli-skill

AI agent skill for querying Grafana Loki logs.

Wraps `logcli` with environment resolution, auto-chunking for large time ranges, and JSON error reporting. The skill prefers a local `logcli` binary and falls back to the `grafana/logcli` Docker image when the binary is missing.

## Installation

```bash
npx skills add vinitu/logcli-skill
```

Upstream package source: `vinitu/logcli-skill`
Installed global skill directory: `~/.agents/skills/logcli/`

Name mapping:

- Repository: `logcli-skill`
- Package source: `vinitu/logcli-skill`
- Installed directory: `logcli`

## Prerequisites

- **bash 4.0+** — `brew install bash` on macOS (macOS ships bash 3.2)
- **jq** — optional, for JSON array formatting in `labels`/`label-values`/`series`
- **shellcheck** — for development only (`make compile`)

Runtime selection is automatic: the shell wrappers prefer local `logcli` and fall back to `grafana/logcli:latest` in Docker.

## Setup

```bash
cp .env.example .env
# Edit .env if you want a local template with LOKI_URL
# Optional: set LOGCLI_BIN to a specific local logcli path
# Optional: set LOGCLI_IMAGE to override the Docker fallback image
# Optional: add LOKI_CHUNK_SECONDS or LOKI_CHUNK_LABEL
```

For agent usage, pass the needed Loki env vars directly with the command:

```bash
LOKI_URL=https://loki.example.com scripts/commands/logs/labels.sh --since 1h
LOKI_URL=https://loki.example.com scripts/commands/logs/query.sh '{job="app"}' --since 30m
```

## Public Interface

Run public commands from the repo root:

- `scripts/commands/logs/query.sh`
- `scripts/commands/logs/labels.sh`
- `scripts/commands/logs/label-values.sh`
- `scripts/commands/logs/series.sh`

`scripts/logcli.sh` still exists as a compatibility wrapper for older automation, but the public interface is `scripts/commands/logs/*.sh`.

## Examples

```bash
# Query logs
LOKI_URL=https://loki.example.com scripts/commands/logs/query.sh '{job="app"}' --since 1h

# Query with explicit URL override
scripts/commands/logs/query.sh '{job="app"}' --since 30m --url https://loki.example.com

# List available labels
LOKI_URL=https://loki.example.com scripts/commands/logs/labels.sh --since 1h

# List values for a label
LOKI_URL=https://loki.example.com scripts/commands/logs/label-values.sh job --since 1h

# List log series
LOKI_URL=https://loki.example.com scripts/commands/logs/series.sh '{job="app"}' --since 1h

# Use a custom Loki URL
scripts/commands/logs/labels.sh --url https://my-loki:3100 --since 1h
```

## Repo Layout

```
logcli-skill/
├── AGENTS.md                  # Rules for coding agents
├── README.md                  # This file
├── SKILL.md                   # Skill contract for AI agents
├── Makefile                   # Validation targets
├── LICENSE                    # MIT
├── .env.example               # Config template
├── .github/
│   └── workflows/
│       ├── ci-pr.yml          # PR validation and auto-merge flow
│       └── ci-main.yml        # Main-branch validation and release flow
├── scripts/
│   ├── commands/
│   │   └── logs/              # Public command surface
│   │       ├── query.sh
│   │       ├── labels.sh
│   │       ├── label-values.sh
│   │       └── series.sh
│   ├── logcli.sh              # Compatibility wrapper
│   └── _lib/
│       └── common.sh          # Internal shared helpers
├── references/
│   └── logql-cheatsheet.md    # LogQL syntax reference
└── tests/
    ├── test_cli_help.sh       # Help and dispatch validation
    ├── test_backend_resolution.sh # Local-vs-Docker backend tests
    ├── test_env_resolution.sh # Environment config tests
    ├── test_chunking.sh       # Time range chunking tests
    └── test_json_output.sh    # JSON contract tests
```

## Validation and Tests

```bash
make check      # Verify prerequisites
make compile    # Shellcheck all scripts
make test       # Run unit tests (no Docker needed)
make test-live  # Run live tests (requires Docker + network)
```

CI workflows:

- `.github/workflows/ci-pr.yml` validates pull requests and controls auto-merge.
- `.github/workflows/ci-main.yml` validates `main` and creates releases.

## Environment Setup

Loki URL comes from the passed `LOKI_URL` env var. The skill does not keep environment names or URL maps.
`.env` is only a local convenience file. The shell wrappers do not read it by themselves.

Example values:

```bash
LOKI_URL=https://loki.example.com
LOKI_CHUNK_SECONDS=3600
```

You can also skip `LOKI_URL` and use `--url` directly.

## Output Contract

- `query.sh` streams log lines to stdout and writes a JSON status envelope to stderr.
- `labels.sh`, `label-values.sh`, and `series.sh` return JSON to stdout.
- Success envelopes include `backend`, which is `local` or `docker:<image>`.
- All failures return JSON to stderr with non-zero exit status.

## Known Limits

- Prefers local `logcli`. Docker is only a fallback runtime.
- Requires bash 4.0+ for associative arrays (macOS default is 3.2).
- Chunk limits come from `LOKI_CHUNK_SECONDS`; otherwise the skill uses a 1h fallback.
- `query.sh` outputs logs to stdout and status to stderr for piping compatibility.
- The repo has no `scripts/applescripts/` directory because this is not a macOS app skill.
- All tests live in top-level `tests/`.

## Unsupported Behaviour

- No write or admin operation exists.
- No fallback exists after both local `logcli` and Docker are unavailable.
- No result caching or local log storage exists.

## License

MIT
