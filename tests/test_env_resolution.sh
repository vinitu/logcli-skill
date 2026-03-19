#!/usr/bin/env bash
set -euo pipefail

# test_env_resolution.sh — validate environment-to-URL resolution

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/../scripts/_lib/common.sh"
PASS=0
FAIL=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  ✗ $label — expected '$expected', got '$actual'"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_fail() {
  local label="$1"
  local exit_code="$2"
  if [[ "$exit_code" -ne 0 ]]; then
    echo "  ✓ $label (failed as expected)"
    PASS=$(( PASS + 1 ))
  else
    echo "  ✗ $label — expected failure, got success"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo "=== test_env_resolution.sh ==="

# Source common in a subshell to avoid polluting current shell
echo "--- URL resolution ---"

# dev environment
result="$(bash -c "source '$COMMON'; resolve_loki_url dev")" && rc=0 || rc=$?
assert_eq "dev resolves to correct URL" "https://loki-dev.example.invalid" "$result"

# rc environment
result="$(bash -c "source '$COMMON'; resolve_loki_url rc")" && rc=0 || rc=$?
assert_eq "rc resolves to correct URL" "https://loki-rc.example.invalid" "$result"

# prod environment
result="$(bash -c "source '$COMMON'; resolve_loki_url prod")" && rc=0 || rc=$?
assert_eq "prod resolves to correct URL" "https://loki-prod.example.invalid" "$result"

# unknown environment
result="$(bash -c "source '$COMMON'; resolve_loki_url unknown" 2>/dev/null)" && rc=0 || rc=$?
assert_fail "unknown env returns error" "$rc"

echo "--- Chunk size resolution ---"

result="$(bash -c "source '$COMMON'; resolve_chunk_seconds dev")"
assert_eq "dev chunk is 21600s (6h)" "21600" "$result"

result="$(bash -c "source '$COMMON'; resolve_chunk_seconds rc")"
assert_eq "rc chunk is 3600s (1h)" "3600" "$result"

result="$(bash -c "source '$COMMON'; resolve_chunk_seconds prod")"
assert_eq "prod chunk is 300s (5m)" "300" "$result"

result="$(bash -c "source '$COMMON'; resolve_chunk_seconds custom")"
assert_eq "custom chunk defaults to 3600s (1h)" "3600" "$result"

echo "--- Chunk labels ---"

result="$(bash -c "source '$COMMON'; resolve_chunk_label dev")"
assert_eq "dev chunk label is 6h" "6h" "$result"

result="$(bash -c "source '$COMMON'; resolve_chunk_label rc")"
assert_eq "rc chunk label is 1h" "1h" "$result"

result="$(bash -c "source '$COMMON'; resolve_chunk_label prod")"
assert_eq "prod chunk label is 5m" "5m" "$result"

echo "--- Config resolution (with env var) ---"

result="$(LOKI_ENV=rc bash -c "source '$COMMON'; resolve_config '' ''; echo \$RESOLVED_URL")"
assert_eq "LOKI_ENV=rc resolves URL" "https://loki-rc.example.invalid" "$result"

result="$(LOKI_ENV=rc LOKI_URL_RC=https://rc-loki.example.test bash -c "source '$COMMON'; resolve_config '' ''; echo \$RESOLVED_URL")"
assert_eq "LOKI_URL_RC overrides default RC URL" "https://rc-loki.example.test" "$result"

result="$(LOKI_URL=https://custom:3100 bash -c "source '$COMMON'; resolve_config '' ''; echo \$RESOLVED_URL")"
assert_eq "LOKI_URL overrides env" "https://custom:3100" "$result"

# Flag overrides env var
result="$(LOKI_ENV=prod bash -c "source '$COMMON'; resolve_config 'dev' ''; echo \$RESOLVED_URL")"
assert_eq "flag --env overrides LOKI_ENV" "https://loki-dev.example.invalid" "$result"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
