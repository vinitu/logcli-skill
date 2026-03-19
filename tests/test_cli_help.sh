#!/usr/bin/env bash
set -euo pipefail

# test_cli_help.sh — validate help output for all commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SCRIPT_DIR/../scripts/logcli.sh"
PASS=0
FAIL=0

assert_contains() {
  local label="$1"
  local output="$2"
  local expected="$3"
  if echo "$output" | grep -qF -- "$expected"; then
    echo "  ✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  ✗ $label — expected '$expected' in output"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_exit_code() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    echo "  ✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  ✗ $label — expected exit $expected, got $actual"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo "=== test_cli_help.sh ==="

# Test: main help
echo "--- main --help ---"
output="$(bash "$CLI" --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "main --help exits 0" 0 "$rc"
assert_contains "shows query command" "$output" "query"
assert_contains "shows labels command" "$output" "labels"
assert_contains "shows label-values command" "$output" "label-values"
assert_contains "shows series command" "$output" "series"

# Test: no args shows help
echo "--- no args ---"
output="$(bash "$CLI" 2>&1)" && rc=0 || rc=$?
assert_exit_code "no args exits 0" 0 "$rc"
assert_contains "shows usage" "$output" "Usage"

# Test: query --help
echo "--- query --help ---"
output="$(bash "$CLI" query --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "query --help exits 0" 0 "$rc"
assert_contains "shows --since flag" "$output" "--since"
assert_contains "shows --from flag" "$output" "--from"
assert_contains "shows --to flag" "$output" "--to"
assert_contains "shows --limit flag" "$output" "--limit"

# Test: labels --help
echo "--- labels --help ---"
output="$(bash "$CLI" labels --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "labels --help exits 0" 0 "$rc"
assert_contains "shows --since flag" "$output" "--since"

# Test: label-values --help
echo "--- label-values --help ---"
output="$(bash "$CLI" label-values --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "label-values --help exits 0" 0 "$rc"
assert_contains "shows label name arg" "$output" "LABEL_NAME"

# Test: series --help
echo "--- series --help ---"
output="$(bash "$CLI" series --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "series --help exits 0" 0 "$rc"
assert_contains "shows selector arg" "$output" "SELECTOR"

# Test: unknown command
echo "--- unknown command ---"
output="$(bash "$CLI" foobar 2>&1)" && rc=0 || rc=$?
assert_exit_code "unknown command exits 1" 1 "$rc"
assert_contains "error mentions unknown command" "$output" "unknown command"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
