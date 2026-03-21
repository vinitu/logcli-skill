#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/_lib/common.sh
source "$ROOT_DIR/scripts/_lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/commands/logs/series.sh '<SELECTOR>' [flags]

Flags:
  --since <dur>   Time range to scan. Default: 1h
  --url <url>     Direct Loki URL. Overrides LOKI_URL
  --help, -h      Show this help

Examples:
  LOKI_URL=https://loki.example.com scripts/commands/logs/series.sh '{job="app"}' --since 1h
  scripts/commands/logs/series.sh '{job="nginx"}' --since 30m --url https://loki.example.com
EOF
}

main() {
  local selector=""
  local since="1h"
  local flag_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --since|--url)
        if [[ $# -lt 2 ]]; then
          usage >&2
          json_fail "missing value for $1"
          exit 1
        fi
        case "$1" in
          --since) since="$2" ;;
          --url) flag_url="$2" ;;
        esac
        shift 2
        ;;
      -*)
        json_fail "unknown flag: $1"
        exit 1
        ;;
      *)
        if [[ -z "$selector" ]]; then
          selector="$1"
          shift
        else
          json_fail "unexpected argument: $1"
          exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$selector" ]]; then
    usage >&2
    json_fail "missing series selector"
    exit 1
  fi

  resolve_config "$flag_url" || exit 1
  ensure_logcli_backend || exit 1

  local stderr_file
  stderr_file="$(mktemp)"
  trap 'rm -f "$stderr_file"' RETURN

  local raw_output
  raw_output="$(run_logcli "$RESOLVED_URL" series "$selector" --since="$since" 2>"$stderr_file")" || {
    local error_message
    error_message="$(head -1 "$stderr_file")"
    [[ -n "$error_message" ]] || error_message="logcli series failed"
    json_fail "logcli series failed: $error_message"
    exit 1
  }

  json_ok "\"command\":\"series\",\"backend\":\"$(logcli_backend_label)\",\"selector\":\"$(json_escape "$selector")\",\"results\":$(json_array_from_lines "$raw_output")"
}

main "$@"
