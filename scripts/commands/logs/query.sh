#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck source=scripts/_lib/common.sh
source "$ROOT_DIR/scripts/_lib/common.sh"

usage() {
  cat <<'EOF'
Usage: scripts/commands/logs/query.sh '<LOGQL>' [flags]

Flags:
  --since <dur>     Relative time range. Default: 1h
  --from <rfc3339>  Absolute start time
  --to <rfc3339>    Absolute end time
  --limit <n>       Max lines per chunk. Default: 5000
  --output <mode>   Output mode: raw, jsonl, default. Default: jsonl
  --url <url>       Direct Loki URL. Overrides LOKI_URL
  --help, -h        Show this help

Examples:
  LOKI_URL=https://loki.example.com scripts/commands/logs/query.sh '{job="app"}' --since 1h
  scripts/commands/logs/query.sh '{job="app", level="error"}' --since 30m --url https://loki.example.com
  scripts/commands/logs/query.sh '{job="app"}' --from 2026-03-18T06:00:00Z --to 2026-03-18T08:00:00Z
EOF
}

run_query_chunk() {
  local query="$1"
  shift

  local stderr_file
  stderr_file="$(mktemp)"
  trap 'rm -f "$stderr_file"' RETURN

  if ! run_logcli "$RESOLVED_URL" query "$query" "$@" 2>"$stderr_file"; then
    local error_message
    error_message="$(head -1 "$stderr_file")"
    [[ -n "$error_message" ]] || error_message="logcli query failed"
    json_fail "logcli query failed: $error_message"
    exit 1
  fi
}

main() {
  local query=""
  local since="1h"
  local from_ts=""
  local to_ts=""
  local limit="$DEFAULT_LIMIT"
  local output="$DEFAULT_OUTPUT"
  local flag_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage
        exit 0
        ;;
      --since|--from|--to|--limit|--output|--url)
        if [[ $# -lt 2 ]]; then
          usage >&2
          json_fail "missing value for $1"
          exit 1
        fi
        case "$1" in
          --since) since="$2" ;;
          --from) from_ts="$2" ;;
          --to) to_ts="$2" ;;
          --limit) limit="$2" ;;
          --output) output="$2" ;;
          --url) flag_url="$2" ;;
        esac
        shift 2
        ;;
      -*)
        json_fail "unknown flag: $1"
        exit 1
        ;;
      *)
        if [[ -z "$query" ]]; then
          query="$1"
          shift
        else
          json_fail "unexpected argument: $1"
          exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$query" ]]; then
    usage >&2
    json_fail "missing LogQL query"
    exit 1
  fi

  resolve_config "$flag_url" || exit 1
  ensure_logcli_backend || exit 1

  local from_epoch=""
  local to_epoch=""
  local total_seconds=""
  local now_epoch
  now_epoch="$(date +%s)"

  if [[ -n "$from_ts" || -n "$to_ts" ]]; then
    if [[ -z "$from_ts" || -z "$to_ts" ]]; then
      json_fail "use --from and --to together"
      exit 1
    fi

    from_epoch="$(rfc3339_to_epoch "$from_ts")"
    to_epoch="$(rfc3339_to_epoch "$to_ts")"

    if [[ "$from_epoch" == "0" || "$to_epoch" == "0" ]]; then
      json_fail "invalid RFC3339 time range"
      exit 1
    fi

    total_seconds=$(( to_epoch - from_epoch ))
    if [[ $total_seconds -le 0 ]]; then
      json_fail "--from must be before --to"
      exit 1
    fi
  else
    total_seconds="$(parse_duration_to_seconds "$since")" || {
      json_fail "invalid duration: $since"
      exit 1
    }
    to_epoch="$now_epoch"
    from_epoch=$(( now_epoch - total_seconds ))
  fi

  local num_chunks
  num_chunks="$(compute_chunks "$total_seconds" "$RESOLVED_CHUNK_SECONDS")"

  if [[ $num_chunks -eq 1 ]]; then
    if [[ -n "$from_ts" ]]; then
      run_query_chunk "$query" \
        --from="$from_ts" \
        --to="$to_ts" \
        --limit="$limit" \
        --output="$output"
    else
      run_query_chunk "$query" \
        --since="$since" \
        --limit="$limit" \
        --output="$output"
    fi
  else
    local boundaries
    boundaries="$(generate_chunk_boundaries "$from_epoch" "$to_epoch" "$RESOLVED_CHUNK_SECONDS")"

    local c_from=""
    local c_to=""
    while IFS=' ' read -r c_from c_to; do
      [[ -z "$c_from" || -z "$c_to" ]] && continue
      run_query_chunk "$query" \
        --from="$(epoch_to_rfc3339 "$c_from")" \
        --to="$(epoch_to_rfc3339 "$c_to")" \
        --limit="$limit" \
        --output="$output"
    done <<< "$boundaries"
  fi

  json_status "\"query\":\"$(json_escape "$query")\",\"chunks\":$num_chunks,\"chunk_limit\":\"$(json_escape "$(resolve_chunk_label)")\",\"backend\":\"$(logcli_backend_label)\""
}

main "$@"
