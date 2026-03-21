#!/usr/bin/env bash
set -euo pipefail

# test_cli_help.sh — validate help output for all commands

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SCRIPT_DIR/../scripts/logcli.sh"
QUERY_CMD="$SCRIPT_DIR/../scripts/commands/logs/query.sh"
LABELS_CMD="$SCRIPT_DIR/../scripts/commands/logs/labels.sh"
LABEL_VALUES_CMD="$SCRIPT_DIR/../scripts/commands/logs/label-values.sh"
SERIES_CMD="$SCRIPT_DIR/../scripts/commands/logs/series.sh"
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

# Test: public query --help
echo "--- scripts/commands/logs/query.sh --help ---"
output="$(bash "$QUERY_CMD" --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "query wrapper --help exits 0" 0 "$rc"
assert_contains "shows --since flag" "$output" "--since"
assert_contains "shows --from flag" "$output" "--from"
assert_contains "shows --to flag" "$output" "--to"
assert_contains "shows --limit flag" "$output" "--limit"

# Test: public labels --help
echo "--- scripts/commands/logs/labels.sh --help ---"
output="$(bash "$LABELS_CMD" --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "labels wrapper --help exits 0" 0 "$rc"
assert_contains "shows --since flag" "$output" "--since"
assert_contains "shows --url flag" "$output" "--url"

# Test: public label-values --help
echo "--- scripts/commands/logs/label-values.sh --help ---"
output="$(bash "$LABEL_VALUES_CMD" --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "label-values wrapper --help exits 0" 0 "$rc"
assert_contains "shows label name arg" "$output" "LABEL_NAME"

# Test: public series --help
echo "--- scripts/commands/logs/series.sh --help ---"
output="$(bash "$SERIES_CMD" --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "series wrapper --help exits 0" 0 "$rc"
assert_contains "shows selector arg" "$output" "SELECTOR"

# Test: legacy dispatch still works
echo "--- legacy query dispatch --help ---"
output="$(bash "$CLI" query --help 2>&1)" && rc=0 || rc=$?
assert_exit_code "legacy query --help exits 0" 0 "$rc"
assert_contains "legacy query dispatch shows public path" "$output" "scripts/commands/logs/query.sh"

# Test: removed --env flag
echo "--- removed --env flag ---"
output="$(bash "$CLI" --env prod query '{job=\"app\"}' 2>&1)" && rc=0 || rc=$?
assert_exit_code "legacy --env exits 1" 1 "$rc"
assert_contains "legacy --env reports unknown flag" "$output" "unknown global flag"

# Test: unknown command
echo "--- unknown command ---"
output="$(bash "$CLI" foobar 2>&1)" && rc=0 || rc=$?
assert_exit_code "unknown command exits 1" 1 "$rc"
assert_contains "error mentions unknown command" "$output" "unknown command"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
