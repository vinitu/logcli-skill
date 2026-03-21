#!/usr/bin/env bash
# shellcheck disable=SC2034
# common.sh — shared helpers for logcli skill
# Source this file; do not execute directly.
# SC2034: Variables are used by the sourcing script (logcli.sh).

# Require bash 4.0+ for associative arrays
if ((BASH_VERSINFO[0] < 4)); then
  echo '{"success":false,"error":"bash 4.0+ required. Install: brew install bash"}' >&2
  exit 1
fi

# --- Path resolution ---

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$COMMON_DIR/../.." && pwd)"
PUBLIC_COMMANDS_DIR="$ROOT_DIR/scripts/commands/logs"

DEFAULT_LIMIT=5000
DEFAULT_OUTPUT="jsonl"
DEFAULT_CHUNK_SECONDS=3600  # 1h fallback for custom URLs
DEFAULT_LOGCLI_IMAGE="grafana/logcli:latest"

# --- JSON helpers ---

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

json_fail() {
  local message
  message="$(json_escape "$1")"
  printf '{"success":false,"error":"%s"}\n' "$message" >&2
  return 1
}

json_ok() {
  local payload="$1"
  printf '{"success":true,%s}\n' "$payload"
}

json_status() {
  # Print status envelope to stderr for query command
  local payload="$1"
  printf '{"success":true,%s}\n' "$payload" >&2
}

json_array_from_lines() {
  local input="${1-}"

  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -R -s 'split("\n") | map(select(length > 0))'
    return 0
  fi

  local json_array="["
  local first=true
  local line

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$first" == "true" ]]; then
      first=false
    else
      json_array+=","
    fi
    json_array+="\"$(json_escape "$line")\""
  done <<< "$input"

  json_array+="]"
  printf '%s\n' "$json_array"
}

# --- Duration parsing ---

# Parse Go-style duration string to seconds
# Supports: 5m, 1h, 6h, 2h30m, 1h15m, 30s, etc.
parse_duration_to_seconds() {
  local input="$1"
  local total=0
  local remaining="$input"

  # Match hours
  if [[ "$remaining" =~ ^([0-9]+)h(.*)$ ]]; then
    total=$(( total + BASH_REMATCH[1] * 3600 ))
    remaining="${BASH_REMATCH[2]}"
  fi

  # Match minutes
  if [[ "$remaining" =~ ^([0-9]+)m(.*)$ ]]; then
    total=$(( total + BASH_REMATCH[1] * 60 ))
    remaining="${BASH_REMATCH[2]}"
  fi

  # Match seconds
  if [[ "$remaining" =~ ^([0-9]+)s(.*)$ ]]; then
    total=$(( total + BASH_REMATCH[1] ))
    remaining="${BASH_REMATCH[2]}"
  fi

  if [[ $total -eq 0 ]]; then
    echo "0"
    return 1
  fi

  echo "$total"
}

# --- RFC3339 helpers ---

# Get current time as RFC3339 (works on both GNU and macOS date)
now_rfc3339() {
  if date --version >/dev/null 2>&1; then
    # GNU date
    date -u '+%Y-%m-%dT%H:%M:%SZ'
  else
    # macOS date
    date -u '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

# Subtract seconds from current time, output RFC3339
time_ago_rfc3339() {
  local seconds="$1"
  if date --version >/dev/null 2>&1; then
    # GNU date
    date -u -d "@$(( $(date +%s) - seconds ))" '+%Y-%m-%dT%H:%M:%SZ'
  else
    # macOS date
    date -u -r $(( $(date +%s) - seconds )) '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

# Convert RFC3339 to epoch seconds
rfc3339_to_epoch() {
  local ts="$1"
  if date --version >/dev/null 2>&1; then
    # GNU date
    date -u -d "$ts" '+%s'
  else
    # macOS date — convert T to space, remove Z, parse
    local cleaned
    cleaned="$(echo "$ts" | sed 's/T/ /;s/Z//')"
    date -u -j -f '%Y-%m-%d %H:%M:%S' "$cleaned" '+%s' 2>/dev/null || echo "0"
  fi
}

# Convert epoch seconds to RFC3339
epoch_to_rfc3339() {
  local epoch="$1"
  if date --version >/dev/null 2>&1; then
    date -u -d "@${epoch}" '+%Y-%m-%dT%H:%M:%SZ'
  else
    date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

# --- Chunking ---

# Compute chunk boundaries for a time range
# Usage: compute_chunks <total_seconds> <chunk_limit_seconds>
# Output: lines of "FROM TO" pairs (RFC3339)
compute_chunks() {
  local total_seconds="$1"
  local chunk_seconds="$2"

  if [[ $total_seconds -le $chunk_seconds ]]; then
    echo "1"
    return 0
  fi

  local num_chunks=$(( (total_seconds + chunk_seconds - 1) / chunk_seconds ))
  echo "$num_chunks"
}

# Generate chunk time boundaries
# Usage: generate_chunk_boundaries <from_epoch> <to_epoch> <chunk_seconds>
# Output: lines of "FROM_EPOCH TO_EPOCH"
generate_chunk_boundaries() {
  local from_epoch="$1"
  local to_epoch="$2"
  local chunk_seconds="$3"

  local current="$from_epoch"
  while [[ $current -lt $to_epoch ]]; do
    local chunk_end=$(( current + chunk_seconds ))
    if [[ $chunk_end -gt $to_epoch ]]; then
      chunk_end="$to_epoch"
    fi
    echo "$current $chunk_end"
    current="$chunk_end"
  done
}

# --- Configuration resolution ---

resolve_loki_url() {
  if [[ -n "${LOKI_URL:-}" ]]; then
    printf '%s\n' "$LOKI_URL"
    return 0
  fi

  return 1
}

resolve_chunk_seconds() {
  printf '%s\n' "${LOKI_CHUNK_SECONDS:-$DEFAULT_CHUNK_SECONDS}"
}

resolve_chunk_label() {
  if [[ -n "${LOKI_CHUNK_LABEL:-}" ]]; then
    printf '%s\n' "$LOKI_CHUNK_LABEL"
    return 0
  fi

  local seconds
  seconds="$(resolve_chunk_seconds)"
  case "$seconds" in
    *[!0-9]*|'')
      printf '1h\n'
      ;;
    60)
      printf '1m\n'
      ;;
    300)
      printf '5m\n'
      ;;
    600)
      printf '10m\n'
      ;;
    1800)
      printf '30m\n'
      ;;
    3600)
      printf '1h\n'
      ;;
    7200)
      printf '2h\n'
      ;;
    21600)
      printf '6h\n'
      ;;
    86400)
      printf '24h\n'
      ;;
    *)
      printf '%ss\n' "$seconds"
      ;;
  esac
}

# --- logcli backend resolution ---

resolve_logcli_binary() {
  if [[ -n "${LOGCLI_BIN:-}" ]]; then
    if [[ -x "${LOGCLI_BIN}" ]]; then
      printf '%s\n' "${LOGCLI_BIN}"
      return 0
    fi
    return 1
  fi

  command -v logcli 2>/dev/null || return 1
}

resolve_logcli_image() {
  printf '%s\n' "${LOGCLI_IMAGE:-$DEFAULT_LOGCLI_IMAGE}"
}

resolve_logcli_backend() {
  local local_binary=""
  if local_binary="$(resolve_logcli_binary)"; then
    RESOLVED_LOGCLI_BACKEND="local"
    RESOLVED_LOGCLI_BIN="$local_binary"
    RESOLVED_LOGCLI_IMAGE=""
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    RESOLVED_LOGCLI_BACKEND="docker"
    RESOLVED_LOGCLI_BIN=""
    RESOLVED_LOGCLI_IMAGE="$(resolve_logcli_image)"
    return 0
  fi

  RESOLVED_LOGCLI_BACKEND=""
  RESOLVED_LOGCLI_BIN=""
  RESOLVED_LOGCLI_IMAGE=""
  return 1
}

ensure_logcli_backend() {
  if resolve_logcli_backend; then
    return 0
  fi

  if [[ -n "${LOGCLI_BIN:-}" ]]; then
    json_fail "LOGCLI_BIN is set but not executable: ${LOGCLI_BIN}"
    return 1
  fi

  json_fail "logcli not found in PATH and docker not found. Install local logcli or Docker to use this skill."
  return 1
}

# Usage: logcli_backend_label
logcli_backend_label() {
  case "${RESOLVED_LOGCLI_BACKEND:-}" in
    local)
      printf 'local\n'
      ;;
    docker)
      printf 'docker:%s\n' "$(json_escape "${RESOLVED_LOGCLI_IMAGE:-$DEFAULT_LOGCLI_IMAGE}")"
      ;;
    *)
      printf 'unknown\n'
      ;;
  esac
}

# Run logcli via the resolved backend.
# Usage: run_logcli <loki_url> <subcommand> [args...]
run_logcli() {
  local loki_url="$1"
  shift

  case "${RESOLVED_LOGCLI_BACKEND:-}" in
    local)
      LOKI_ADDR="$loki_url" "$RESOLVED_LOGCLI_BIN" "$@"
      ;;
    docker)
      docker run --rm -e LOKI_ADDR="$loki_url" "$RESOLVED_LOGCLI_IMAGE" "$@"
      ;;
    *)
      json_fail "logcli backend is not resolved"
      return 1
      ;;
  esac
}

resolve_config() {
  local flag_url="${1:-}"
  local url="${flag_url:-}"

  if [[ -z "$url" ]]; then
    RESOLVED_URL="$(resolve_loki_url)" || {
      json_fail "missing exported LOKI_URL. Pass LOKI_URL with the command or use --url."
      return 1
    }
  else
    RESOLVED_URL="$url"
  fi

  RESOLVED_CHUNK_SECONDS="$(resolve_chunk_seconds)"
}
