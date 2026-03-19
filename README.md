# logcli-skill

AI agent skill for querying Grafana Loki logs via the `grafana/logcli` Docker image.

Wraps `grafana/logcli` with environment resolution, auto-chunking for large time ranges, and JSON error reporting.

## Installation

```bash
npx skills add vinitu/logcli-skill
```

Installs to: `~/.agents/skills/logcli/`

**Note:** The GitHub repository is `logcli-skill`, but the installed skill directory is `logcli`.

## Prerequisites

- **Docker** — all Loki queries run inside `docker run grafana/logcli:latest`
- **bash 4.0+** — `brew install bash` on macOS (macOS ships bash 3.2)
- **jq** — optional, for JSON array formatting in `labels`/`label-values`/`series`
- **shellcheck** — for development only (`make compile`)

Pull the Docker image before first use:

```bash
docker pull grafana/logcli:latest
```

## Setup

```bash
cp .env.example .env
# Edit .env — set LOKI_ENV to dev, rc, or prod
# Optional: set LOKI_URL_DEV / LOKI_URL_RC / LOKI_URL_PROD with real endpoints
# Optional: set LOKI_URL to bypass env mapping for one direct endpoint
```

## Usage

```bash
# Query logs
scripts/logcli.sh query '{job="app"}' --since 1h

# Query with environment override
scripts/logcli.sh query '{job="app"}' --since 30m --env prod

# List available labels
scripts/logcli.sh labels --since 1h

# List values for a label
scripts/logcli.sh label-values job --since 1h

# List log series
scripts/logcli.sh series '{job="app"}' --since 1h

# Use a custom Loki URL
scripts/logcli.sh labels --url https://my-loki:3100 --since 1h
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
├── scripts/
│   ├── logcli.sh              # CLI entrypoint
│   └── _lib/
│       └── common.sh          # Shared helpers
├── references/
│   └── logql-cheatsheet.md    # LogQL syntax reference
└── tests/
    ├── test_cli_help.sh       # Help output validation
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

## Environments

| Environment | Loki URL | Max Query Window |
|-------------|----------|-----------------|
| dev (default) | `https://loki-dev.example.invalid` | 6h |
| rc | `https://loki-rc.example.invalid` | 1h |
| prod | `https://loki-prod.example.invalid` | 5m |

These are safe placeholder defaults. Set real endpoints in `.env` or shell env vars.

## Known Limits

- Requires Docker for all Loki operations — no native HTTP client.
- Requires bash 4.0+ for associative arrays (macOS default is 3.2).
- Chunk limits are per-environment; the script auto-splits but does not merge partial results.
- The `query` command outputs logs to stdout and status to stderr (for piping compatibility).

## License

MIT
