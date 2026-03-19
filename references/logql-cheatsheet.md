# LogQL Cheatsheet

Quick reference for LogQL queries used with `scripts/logcli.sh`.

## CLI-to-logcli Mapping

| CLI Command | logcli Subcommand | Description |
|-------------|-------------------|-------------|
| `logcli.sh query '<QUERY>'` | `logcli query '<QUERY>'` | Run a log query |
| `logcli.sh labels` | `logcli labels` | List label names |
| `logcli.sh label-values <NAME>` | `logcli labels <NAME>` | List label values |
| `logcli.sh series '<SELECTOR>'` | `logcli series '<SELECTOR>'` | List matching series |

## Stream Selectors

```logql
{job="app"}                          # exact match
{job=~"app|web"}                     # regex match
{job!="test"}                        # not equal
{job!~"test.*"}                      # regex not match
{job="app", level="error"}           # multiple labels (AND)
```

## Line Filters

```logql
{job="app"} |= "error"              # contains "error"
{job="app"} != "debug"              # does not contain "debug"
{job="app"} |~ "error|warning"      # regex match
{job="app"} !~ "health.*check"      # regex not match
```

## Pipeline Stages

```logql
# Parse JSON logs
{job="app"} | json

# Parse logfmt
{job="app"} | logfmt

# Extract with regex
{job="app"} | regexp `(?P<method>\w+) (?P<path>/\S+)`

# Filter after parsing
{job="app"} | json | level="error"
{job="app"} | json | response_time > 1.0

# Format output
{job="app"} | json | line_format "{{.level}} {{.message}}"
```

## Time Range Examples

```bash
# Last 30 minutes
scripts/logcli.sh query '{job="app"}' --since 30m

# Last 6 hours
scripts/logcli.sh query '{job="app"}' --since 6h

# Specific time window
scripts/logcli.sh query '{job="app"}' \
  --from 2026-03-18T06:00:00Z \
  --to 2026-03-18T08:00:00Z

# Prod with auto-chunking (5m chunks)
scripts/logcli.sh query '{job="app"}' --since 15m --env prod
# ↑ runs 3 sequential 5-minute queries
```

## Output Modes

```bash
# JSON lines (default) — one JSON object per log line
scripts/logcli.sh query '{job="app"}' --since 1h --output jsonl

# Raw — unformatted logcli output
scripts/logcli.sh query '{job="app"}' --since 1h --output raw

# Default — logcli default formatting
scripts/logcli.sh query '{job="app"}' --since 1h --output default
```

## Useful Patterns

```bash
# Pipe to grep for quick filtering
scripts/logcli.sh query '{job="app"}' --since 1h | grep ERROR

# Pipe to jq for JSON processing
scripts/logcli.sh query '{job="app"}' --since 1h --output jsonl | jq '.message'

# Count errors
scripts/logcli.sh query '{job="app"}' --since 1h | grep -c ERROR

# Save to file
scripts/logcli.sh query '{job="app"}' --since 1h > /tmp/logs.txt
```

## References

- [LogQL documentation](https://grafana.com/docs/loki/latest/query/)
- [logcli documentation](https://grafana.com/docs/loki/latest/tools/logcli/)
