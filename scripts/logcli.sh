#!/usr/bin/env bash
set -euo pipefail

# logcli.sh — CLI entrypoint for Loki LogCLI skill
# Wraps grafana/logcli Docker image with environment resolution and auto-chunking.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_lib/common.sh
source "$SCRIPT_DIR/_lib/common.sh"

# --- Usage ---

usage() {
  cat <<'EOF'
Usage: logcli.sh <command> [flags]

Commands:
  query           Run a LogQL query
  labels          List available label names
  label-values    List values for a specific label
  series          List log series matching a selector

Global flags:
  --env <name>    Environment: dev, rc, prod (default: dev)
  --url <url>     Direct Loki URL (overrides --env)
  --help, -h      Show this help

Examples:
  logcli.sh query '{job="app"}' --since 1h
  logcli.sh query '{job="app"}' --since 1h --env prod
  logcli.sh labels --since 1h
  logcli.sh label-values job --since 1h
  logcli.sh series '{job="app"}' --since 1h
EOF
}

usage_query() {
  cat <<'EOF'
Usage: logcli.sh query '<LOGQL>' [flags]

Flags:
  --since <dur>     Relative time range (e.g. 1h, 30m, 6h). Default: 1h
  --from  <rfc3339> Absolute start time (e.g. 2026-03-18T08:00:00Z)
  --to    <rfc3339> Absolute end time (e.g. 2026-03-18T09:00:00Z)
  --limit <n>       Max lines per chunk (default: 5000)
  --output <mode>   Output mode: raw, jsonl, default (default: jsonl)
  --env <name>      Environment: dev, rc, prod (default: dev)
  --url <url>       Direct Loki URL (overrides --env)

Auto-chunking:
  If the time range exceeds the environment chunk limit, the query is
  automatically split into sequential chunks.

  Chunk limits: dev=6h, rc=1h, prod=5m

Examples:
  logcli.sh query '{job="app"}' --since 1h
  logcli.sh query '{job="app", level="error"}' --since 30m --env prod
  logcli.sh query '{job="app"}' --from 2026-03-18T06:00:00Z --to 2026-03-18T08:00:00Z
EOF
}

usage_labels() {
  cat <<'EOF'
Usage: logcli.sh labels [flags]

Flags:
  --since <dur>   Time range to scan (default: 1h)
  --env <name>    Environment (default: dev)
  --url <url>     Direct Loki URL

Examples:
  logcli.sh labels --since 1h
  logcli.sh labels --since 1h --env prod
EOF
}

usage_label_values() {
  cat <<'EOF'
Usage: logcli.sh label-values <LABEL_NAME> [flags]

Flags:
  --since <dur>   Time range to scan (default: 1h)
  --env <name>    Environment (default: dev)
  --url <url>     Direct Loki URL

Examples:
  logcli.sh label-values job --since 1h
  logcli.sh label-values type --since 1h --env rc
EOF
}

usage_series() {
  cat <<'EOF'
Usage: logcli.sh series '<SELECTOR>' [flags]

Flags:
  --since <dur>   Time range to scan (default: 1h)
  --env <name>    Environment (default: dev)
  --url <url>     Direct Loki URL

Examples:
  logcli.sh series '{job="app"}' --since 1h
  logcli.sh series '{job="nginx"}' --since 30m --env prod
EOF
}

# --- Command: query ---

cmd_query() {
  local query=""
  local since="1h"
  local from_ts=""
  local to_ts=""
  local limit="$DEFAULT_LIMIT"
  local output="$DEFAULT_OUTPUT"
  local flag_env=""
  local flag_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage_query; exit 0 ;;
      --since)  since="$2"; shift 2 ;;
      --from)   from_ts="$2"; shift 2 ;;
      --to)     to_ts="$2"; shift 2 ;;
      --limit)  limit="$2"; shift 2 ;;
      --output) output="$2"; shift 2 ;;
      --env)    flag_env="$2"; shift 2 ;;
      --url)    flag_url="$2"; shift 2 ;;
      -*)       json_fail "unknown flag: $1"; exit 1 ;;
      *)
        if [[ -z "$query" ]]; then
          query="$1"; shift
        else
          json_fail "unexpected argument: $1"; exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$query" ]]; then
    usage_query >&2
    json_fail "missing LogQL query"
    exit 1
  fi

  # Resolve config
  resolve_config "$flag_env" "$flag_url" || exit 1

  # Check Docker
  if ! command -v docker >/dev/null 2>&1; then
    json_fail "docker not found. Install Docker to use this skill."
    exit 1
  fi

  # Determine time range
  local from_epoch to_epoch total_seconds
  local now_epoch
  now_epoch="$(date +%s)"

  if [[ -n "$from_ts" && -n "$to_ts" ]]; then
    from_epoch="$(rfc3339_to_epoch "$from_ts")"
    to_epoch="$(rfc3339_to_epoch "$to_ts")"
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

  # Compute chunks
  local num_chunks
  num_chunks="$(compute_chunks "$total_seconds" "$RESOLVED_CHUNK_SECONDS")"

  local total_lines=0

  if [[ $num_chunks -eq 1 ]]; then
    # Single chunk — use --since for simplicity when no absolute range given
    if [[ -n "$from_ts" && -n "$to_ts" ]]; then
      run_logcli "$RESOLVED_URL" query "$query" \
        --from="$from_ts" --to="$to_ts" \
        --limit="$limit" --output="$output" && true
    else
      run_logcli "$RESOLVED_URL" query "$query" \
        --since="$since" \
        --limit="$limit" --output="$output" && true
    fi
    total_lines=$(( total_lines + 1 ))  # approximate
  else
    # Multiple chunks
    local boundaries
    boundaries="$(generate_chunk_boundaries "$from_epoch" "$to_epoch" "$RESOLVED_CHUNK_SECONDS")"

    local chunk_idx=0
    while IFS=' ' read -r c_from c_to; do
      chunk_idx=$(( chunk_idx + 1 ))
      local c_from_rfc
      c_from_rfc="$(epoch_to_rfc3339 "$c_from")"
      local c_to_rfc
      c_to_rfc="$(epoch_to_rfc3339 "$c_to")"

      run_logcli "$RESOLVED_URL" query "$query" \
        --from="$c_from_rfc" --to="$c_to_rfc" \
        --limit="$limit" --output="$output" && true
    done <<< "$boundaries"
  fi

  # Status to stderr
  local chunk_label
  chunk_label="$(resolve_chunk_label "$RESOLVED_ENV")"
  local escaped_query="${query//\"/\\\"}"
  json_status "\"env\":\"$RESOLVED_ENV\",\"query\":\"$escaped_query\",\"chunks\":$num_chunks,\"chunk_limit\":\"$chunk_label\""
}

# --- Command: labels ---

cmd_labels() {
  local since="1h"
  local flag_env=""
  local flag_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage_labels; exit 0 ;;
      --since)   since="$2"; shift 2 ;;
      --env)     flag_env="$2"; shift 2 ;;
      --url)     flag_url="$2"; shift 2 ;;
      -*)        json_fail "unknown flag: $1"; exit 1 ;;
      *)         json_fail "unexpected argument: $1"; exit 1 ;;
    esac
  done

  resolve_config "$flag_env" "$flag_url" || exit 1

  if ! command -v docker >/dev/null 2>&1; then
    json_fail "docker not found"
    exit 1
  fi

  local raw_output
  raw_output="$(run_logcli "$RESOLVED_URL" labels --since="$since" 2>&1)" || {
    json_fail "logcli labels failed: $(echo "$raw_output" | head -1)"
    exit 1
  }

  # Convert newline-separated labels to JSON array
  local json_array
  if command -v jq >/dev/null 2>&1; then
    json_array="$(echo "$raw_output" | jq -R -s 'split("\n") | map(select(length > 0))')"
  else
    # Fallback: manual JSON array
    json_array="["
    local first=true
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if [[ "$first" == "true" ]]; then
        first=false
      else
        json_array+=","
      fi
      json_array+="\"$line\""
    done <<< "$raw_output"
    json_array+="]"
  fi

  json_ok "\"env\":\"$RESOLVED_ENV\",\"command\":\"labels\",\"results\":$json_array"
}

# --- Command: label-values ---

cmd_label_values() {
  local label_name=""
  local since="1h"
  local flag_env=""
  local flag_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage_label_values; exit 0 ;;
      --since)   since="$2"; shift 2 ;;
      --env)     flag_env="$2"; shift 2 ;;
      --url)     flag_url="$2"; shift 2 ;;
      -*)        json_fail "unknown flag: $1"; exit 1 ;;
      *)
        if [[ -z "$label_name" ]]; then
          label_name="$1"; shift
        else
          json_fail "unexpected argument: $1"; exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$label_name" ]]; then
    usage_label_values >&2
    json_fail "missing label name"
    exit 1
  fi

  resolve_config "$flag_env" "$flag_url" || exit 1

  if ! command -v docker >/dev/null 2>&1; then
    json_fail "docker not found"
    exit 1
  fi

  local raw_output
  raw_output="$(run_logcli "$RESOLVED_URL" labels "$label_name" --since="$since" 2>&1)" || {
    json_fail "logcli label-values failed: $(echo "$raw_output" | head -1)"
    exit 1
  }

  local json_array
  if command -v jq >/dev/null 2>&1; then
    json_array="$(echo "$raw_output" | jq -R -s 'split("\n") | map(select(length > 0))')"
  else
    json_array="["
    local first=true
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ "$first" == "true" ]] && first=false || json_array+=","
      json_array+="\"$line\""
    done <<< "$raw_output"
    json_array+="]"
  fi

  json_ok "\"env\":\"$RESOLVED_ENV\",\"command\":\"label-values\",\"label\":\"$label_name\",\"results\":$json_array"
}

# --- Command: series ---

cmd_series() {
  local selector=""
  local since="1h"
  local flag_env=""
  local flag_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) usage_series; exit 0 ;;
      --since)   since="$2"; shift 2 ;;
      --env)     flag_env="$2"; shift 2 ;;
      --url)     flag_url="$2"; shift 2 ;;
      -*)        json_fail "unknown flag: $1"; exit 1 ;;
      *)
        if [[ -z "$selector" ]]; then
          selector="$1"; shift
        else
          json_fail "unexpected argument: $1"; exit 1
        fi
        ;;
    esac
  done

  if [[ -z "$selector" ]]; then
    usage_series >&2
    json_fail "missing series selector"
    exit 1
  fi

  resolve_config "$flag_env" "$flag_url" || exit 1

  if ! command -v docker >/dev/null 2>&1; then
    json_fail "docker not found"
    exit 1
  fi

  local raw_output
  raw_output="$(run_logcli "$RESOLVED_URL" series "$selector" --since="$since" 2>&1)" || {
    json_fail "logcli series failed: $(echo "$raw_output" | head -1)"
    exit 1
  }

  local json_array
  if command -v jq >/dev/null 2>&1; then
    json_array="$(echo "$raw_output" | jq -R -s 'split("\n") | map(select(length > 0))')"
  else
    json_array="["
    local first=true
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ "$first" == "true" ]] && first=false || json_array+=","
      json_array+="\"$line\""
    done <<< "$raw_output"
    json_array+="]"
  fi

  local escaped_selector="${selector//\"/\\\"}"
  json_ok "\"env\":\"$RESOLVED_ENV\",\"command\":\"series\",\"selector\":\"$escaped_selector\",\"results\":$json_array"
}

# --- Main dispatcher ---

main() {
  local flag_env=""
  local flag_url=""

  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  # Parse global flags before subcommand.
  # Once we hit a non-flag argument (the subcommand), stop parsing globals
  # and pass everything remaining to the subcommand handler.
  local args=()
  local found_cmd=false
  while [[ $# -gt 0 ]]; do
    if [[ "$found_cmd" == "true" ]]; then
      args+=("$1")
      shift
      continue
    fi
    case "$1" in
      --help|-h) usage; exit 0 ;;
      --env)
        flag_env="$2"
        args+=(--env "$2")
        shift 2
        ;;
      --url)
        flag_url="$2"
        args+=(--url "$2")
        shift 2
        ;;
      -*)
        # Unknown global flag — pass to subcommand
        args+=("$1")
        shift
        ;;
      *)
        # First non-flag arg is the subcommand
        args+=("$1")
        found_cmd=true
        shift
        ;;
    esac
  done

  # First non-flag arg is the subcommand
  if [[ ${#args[@]} -eq 0 ]]; then
    usage
    exit 0
  fi

  local cmd="${args[0]}"
  local cmd_args=("${args[@]:1}")

  case "$cmd" in
    query)        cmd_query "${cmd_args[@]}" ;;
    labels)       cmd_labels "${cmd_args[@]}" ;;
    label-values) cmd_label_values "${cmd_args[@]}" ;;
    series)       cmd_series "${cmd_args[@]}" ;;
    *)
      json_fail "unknown command: $cmd. Run with --help for usage."
      exit 1
      ;;
  esac
}

main "$@"
