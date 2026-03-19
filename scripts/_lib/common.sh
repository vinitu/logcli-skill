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

# --- Environment mapping ---

declare -A LOKI_URLS=(
  [dev]="https://loki-dev.example.invalid"
  [rc]="https://loki-rc.example.invalid"
  [prod]="https://loki-prod.example.invalid"
)

declare -A LOKI_CHUNK_SECONDS=(
  [dev]=21600   # 6h
  [rc]=3600     # 1h
  [prod]=300    # 5m
)

declare -A LOKI_CHUNK_LABELS=(
  [dev]="6h"
  [rc]="1h"
  [prod]="5m"
)

DEFAULT_ENV="dev"
DEFAULT_LIMIT=5000
DEFAULT_OUTPUT="jsonl"
DEFAULT_CHUNK_SECONDS=3600  # 1h fallback for custom URLs

# --- .env loader ---

load_dotenv() {
  local env_file="${ROOT_DIR}/.env"
  if [[ -f "$env_file" ]]; then
    while IFS='=' read -r key value; do
      # Skip comments and empty lines
      [[ "$key" =~ ^[[:space:]]*# ]] && continue
      [[ -z "$key" ]] && continue
      key="$(echo "$key" | xargs)"
      value="$(echo "$value" | xargs)"
      # Only set if not already in environment
      if [[ -z "${!key:-}" ]]; then
        export "$key=$value"
      fi
    done < "$env_file"
  fi
}

# --- JSON helpers ---

json_fail() {
  local message="$1"
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

# --- Environment resolution ---

# Resolve environment name to Loki URL
# Usage: resolve_env <env_name>
resolve_loki_url() {
  local env_name="$1"
  local env_var_name="LOKI_URL_${env_name^^}"
  local env_var_url="${!env_var_name:-}"
  local url="${env_var_url:-${LOKI_URLS[$env_name]:-}}"
  if [[ -z "$url" ]]; then
    return 1
  fi
  echo "$url"
}

# Get chunk size in seconds for an environment
resolve_chunk_seconds() {
  local env_name="$1"
  echo "${LOKI_CHUNK_SECONDS[$env_name]:-$DEFAULT_CHUNK_SECONDS}"
}

# Get chunk size label for an environment
resolve_chunk_label() {
  local env_name="$1"
  echo "${LOKI_CHUNK_LABELS[$env_name]:-1h}"
}

# --- Docker wrapper ---

# Run logcli via Docker
# Usage: run_logcli <loki_url> <subcommand> [args...]
run_logcli() {
  local loki_url="$1"
  shift
  docker run --rm -e LOKI_ADDR="$loki_url" grafana/logcli:latest "$@"
}

# --- Config resolution ---

# Resolve final config from flags, env vars, and .env
# Sets global variables: RESOLVED_URL, RESOLVED_ENV, RESOLVED_CHUNK_SECONDS
resolve_config() {
  local flag_env="${1:-}"
  local flag_url="${2:-}"

  # Load .env (only sets vars not already in environment)
  load_dotenv

  # Determine environment
  local env_name="${flag_env:-${LOKI_ENV:-$DEFAULT_ENV}}"

  # Determine URL
  local url="${flag_url:-${LOKI_URL:-}}"

  if [[ -n "$url" ]]; then
    # Direct URL provided — use it
    RESOLVED_URL="$url"
    RESOLVED_ENV="${env_name}"
    RESOLVED_CHUNK_SECONDS="$(resolve_chunk_seconds "$env_name")"
  else
    # Resolve from environment name
    RESOLVED_URL="$(resolve_loki_url "$env_name")" || {
      json_fail "unknown environment: ${env_name}. Valid: dev, rc, prod (or use --url)"
      return 1
    }
    RESOLVED_ENV="$env_name"
    RESOLVED_CHUNK_SECONDS="$(resolve_chunk_seconds "$env_name")"
  fi
}
