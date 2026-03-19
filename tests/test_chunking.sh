#!/usr/bin/env bash
set -euo pipefail

# test_chunking.sh — validate duration parsing and chunk computation

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

echo "=== test_chunking.sh ==="

echo "--- Duration parsing ---"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '5m'")"
assert_eq "5m = 300s" "300" "$result"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '1h'")"
assert_eq "1h = 3600s" "3600" "$result"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '6h'")"
assert_eq "6h = 21600s" "21600" "$result"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '2h30m'")"
assert_eq "2h30m = 9000s" "9000" "$result"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '1h15m'")"
assert_eq "1h15m = 4500s" "4500" "$result"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '30m'")"
assert_eq "30m = 1800s" "1800" "$result"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '45s'")"
assert_eq "45s = 45s" "45" "$result"

result="$(bash -c "source '$COMMON'; parse_duration_to_seconds '1h30m45s'")"
assert_eq "1h30m45s = 5445s" "5445" "$result"

echo "--- Chunk computation ---"

# Single chunk (within limit)
result="$(bash -c "source '$COMMON'; compute_chunks 3600 21600")"
assert_eq "1h in dev (6h limit) = 1 chunk" "1" "$result"

result="$(bash -c "source '$COMMON'; compute_chunks 300 300")"
assert_eq "5m in prod (5m limit) = 1 chunk" "1" "$result"

result="$(bash -c "source '$COMMON'; compute_chunks 21600 21600")"
assert_eq "6h in dev (6h limit) = 1 chunk" "1" "$result"

# Multiple chunks
result="$(bash -c "source '$COMMON'; compute_chunks 43200 21600")"
assert_eq "12h in dev (6h limit) = 2 chunks" "2" "$result"

result="$(bash -c "source '$COMMON'; compute_chunks 900 300")"
assert_eq "15m in prod (5m limit) = 3 chunks" "3" "$result"

result="$(bash -c "source '$COMMON'; compute_chunks 7200 3600")"
assert_eq "2h in rc (1h limit) = 2 chunks" "2" "$result"

# Ceiling division
result="$(bash -c "source '$COMMON'; compute_chunks 25200 21600")"
assert_eq "7h in dev (6h limit) = 2 chunks (ceiling)" "2" "$result"

result="$(bash -c "source '$COMMON'; compute_chunks 400 300")"
assert_eq "6m40s in prod (5m limit) = 2 chunks (ceiling)" "2" "$result"

echo "--- Chunk boundary generation ---"

# 2 chunks: 0..600 with 300s chunks
boundaries="$(bash -c "source '$COMMON'; generate_chunk_boundaries 1000 1600 300")"
line_count="$(echo "$boundaries" | wc -l | xargs)"
assert_eq "600s / 300s chunks = 2 boundaries" "2" "$line_count"

# Verify first and last boundaries
first_line="$(echo "$boundaries" | head -1)"
last_line="$(echo "$boundaries" | tail -1)"
assert_eq "first chunk starts at 1000" "1000 1300" "$first_line"
assert_eq "last chunk ends at 1600" "1300 1600" "$last_line"

# 3 chunks: 0..1000 with 400s chunks
boundaries="$(bash -c "source '$COMMON'; generate_chunk_boundaries 0 1000 400")"
line_count="$(echo "$boundaries" | wc -l | xargs)"
assert_eq "1000s / 400s chunks = 3 boundaries" "3" "$line_count"

first_line="$(echo "$boundaries" | head -1)"
last_line="$(echo "$boundaries" | tail -1)"
assert_eq "first boundary is 0 400" "0 400" "$first_line"
assert_eq "last boundary ends at 1000" "800 1000" "$last_line"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
