#!/usr/bin/env bash
set -euo pipefail

# test_json_output.sh — validate JSON contract for error and success cases

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$SCRIPT_DIR/../scripts/logcli.sh"
QUERY_CMD="$SCRIPT_DIR/../scripts/commands/logs/query.sh"
LABEL_VALUES_CMD="$SCRIPT_DIR/../scripts/commands/logs/label-values.sh"
SERIES_CMD="$SCRIPT_DIR/../scripts/commands/logs/series.sh"
COMMON="$SCRIPT_DIR/../scripts/_lib/common.sh"
BASH_BIN="$(command -v bash)"
PASS=0
FAIL=0

assert_json_field() {
  local label="$1"
  local json="$2"
  local field="$3"
  local expected="$4"

  if ! command -v jq >/dev/null 2>&1; then
    echo "  ⊘ $label (skipped: jq not available)"
    return
  fi

  local actual
  actual="$(echo "$json" | jq -r "$field" 2>/dev/null)" || {
    echo "  ✗ $label — failed to parse JSON"
    FAIL=$(( FAIL + 1 ))
    return
  }

  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  ✗ $label — expected '$expected', got '$actual'"
    FAIL=$(( FAIL + 1 ))
  fi
}

assert_valid_json() {
  local label="$1"
  local json="$2"

  if ! command -v jq >/dev/null 2>&1; then
    echo "  ⊘ $label (skipped: jq not available)"
    return
  fi

  if echo "$json" | jq . >/dev/null 2>&1; then
    echo "  ✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  ✗ $label — invalid JSON: $json"
    FAIL=$(( FAIL + 1 ))
  fi
}

echo "=== test_json_output.sh ==="

echo "--- Error output: missing query ---"
output="$(bash "$QUERY_CMD" 2>&1)" || true
# Filter to just the JSON line (skip usage text)
json_line="$(echo "$output" | grep '"success"' | tail -1)"
assert_valid_json "missing query produces valid JSON" "$json_line"
assert_json_field "success is false" "$json_line" '.success' "false"
assert_json_field "error mentions missing" "$json_line" '.error' "missing LogQL query"

echo "--- Error output: unknown command ---"
output="$(bash "$CLI" badcommand 2>&1)" || true
assert_valid_json "unknown command produces valid JSON" "$output"
assert_json_field "success is false" "$output" '.success' "false"

echo "--- Error output: missing label name ---"
output="$(bash "$LABEL_VALUES_CMD" 2>&1)" || true
# Filter to just the JSON line (skip usage text)
json_line="$(echo "$output" | grep '"success"' | tail -1)"
assert_valid_json "missing label produces valid JSON" "$json_line"
assert_json_field "success is false" "$json_line" '.success' "false"

echo "--- Error output: missing series selector ---"
output="$(bash "$SERIES_CMD" 2>&1)" || true
json_line="$(echo "$output" | grep '"success"' | tail -1)"
assert_valid_json "missing selector produces valid JSON" "$json_line"
assert_json_field "success is false" "$json_line" '.success' "false"

echo "--- Error output: missing LOKI_URL ---"
output="$(bash "$QUERY_CMD" '{job="x"}' 2>&1)" || true
json_line="$(echo "$output" | grep '"success"' | tail -1)"
assert_valid_json "missing LOKI_URL produces valid JSON" "$json_line"
assert_json_field "success is false" "$json_line" '.success' "false"

echo "--- JSON helpers: json_fail ---"
output="$(bash -c "source '$COMMON'; json_fail 'test error message'" 2>&1)" || true
assert_valid_json "json_fail is valid JSON" "$output"
assert_json_field "json_fail success is false" "$output" '.success' "false"
assert_json_field "json_fail has error message" "$output" '.error' "test error message"

echo "--- JSON helpers: json_ok ---"
output="$(bash -c "source '$COMMON'; json_ok '\"test\":\"value\"'")"
assert_valid_json "json_ok is valid JSON" "$output"
assert_json_field "json_ok success is true" "$output" '.success' "true"
assert_json_field "json_ok has payload" "$output" '.test' "value"

echo "--- Backend label output ---"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cat > "$tmp_dir/logcli" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/logcli"
output="$(COMMON_PATH="$COMMON" PATH="$tmp_dir:/usr/bin:/bin" "$BASH_BIN" -c "source \"\$COMMON_PATH\"; resolve_logcli_backend; backend=\"\$(logcli_backend_label)\"; json_ok \"\\\"backend\\\":\\\"\${backend}\\\"\"")"
assert_valid_json "backend label payload is valid JSON" "$output"
assert_json_field "backend label is local" "$output" '.backend' "local"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
