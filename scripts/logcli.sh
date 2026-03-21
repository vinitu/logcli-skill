#!/usr/bin/env bash
set -euo pipefail

# logcli.sh — compatibility entrypoint for Loki LogCLI skill
# Prefer scripts/commands/logs/*.sh for the public interface.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_lib/common.sh
source "$SCRIPT_DIR/_lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/logcli.sh [--url <url>] <command> [args]

Commands:
  query           Run scripts/commands/logs/query.sh
  labels          Run scripts/commands/logs/labels.sh
  label-values    Run scripts/commands/logs/label-values.sh
  series          Run scripts/commands/logs/series.sh

Global flags:
  --url <url>     Forward direct Loki URL to the public command
  --help, -h      Show this help and exit

Examples:
  LOKI_URL=https://loki.example.com scripts/logcli.sh query '{job="app"}' --since 1h
  scripts/logcli.sh --url https://loki.example.com labels --since 1h
  LOKI_URL=https://loki.example.com scripts/commands/logs/query.sh '{job="app"}' --since 1h

Public interface:
  scripts/commands/logs/query.sh
  scripts/commands/logs/labels.sh
  scripts/commands/logs/label-values.sh
  scripts/commands/logs/series.sh
EOF
}

command_script_path() {
  local command_name="$1"

  case "$command_name" in
    query|labels|label-values|series)
      printf '%s/%s.sh\n' "$PUBLIC_COMMANDS_DIR" "$command_name"
      ;;
    *)
      return 1
      ;;
  esac
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  local forwarded=()
  local command_name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --url)
        if [[ $# -lt 2 ]]; then
          usage >&2
          json_fail "missing value for --url"
          exit 1
        fi
        forwarded+=(--url "$2")
        shift 2
        ;;
      -*)
        json_fail "unknown global flag: $1"
        exit 1
        ;;
      *)
        command_name="$1"
        shift
        break
        ;;
    esac
  done

  if [[ -z "$command_name" ]]; then
    usage
    exit 0
  fi

  local command_script
  command_script="$(command_script_path "$command_name")" || {
    json_fail "unknown command: $command_name. Run with --help for usage."
    exit 1
  }

  if [[ ! -f "$command_script" ]]; then
    json_fail "command wrapper not found: $command_script"
    exit 1
  fi

  exec bash "$command_script" "${forwarded[@]}" "$@"
}

main "$@"
