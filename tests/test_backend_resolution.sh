#!/usr/bin/env bash
set -euo pipefail

# test_backend_resolution.sh — validate logcli backend preference and fallback

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON="$SCRIPT_DIR/../scripts/_lib/common.sh"
BASH_BIN="$(command -v bash)"
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

assert_contains() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    echo "  ✓ $label"
    PASS=$(( PASS + 1 ))
  else
    echo "  ✗ $label — expected '$expected' in '$actual'"
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

echo "=== test_backend_resolution.sh ==="

echo "--- prefers local logcli from PATH ---"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cat > "$tmp_dir/logcli" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/logcli"

result="$(PATH="$tmp_dir:/usr/bin:/bin" "$BASH_BIN" -c "source '$COMMON'; resolve_logcli_backend; echo \$RESOLVED_LOGCLI_BACKEND:\$RESOLVED_LOGCLI_BIN")"
assert_contains "backend is local" "$result" "local:"
assert_contains "uses temp logcli path" "$result" "$tmp_dir/logcli"

echo "--- LOGCLI_BIN overrides PATH ---"
custom_bin="$tmp_dir/custom-logcli"
cat > "$custom_bin" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$custom_bin"
result="$(LOGCLI_BIN="$custom_bin" PATH="/usr/bin:/bin" "$BASH_BIN" -c "source '$COMMON'; resolve_logcli_backend; echo \$RESOLVED_LOGCLI_BACKEND:\$RESOLVED_LOGCLI_BIN")"
assert_eq "LOGCLI_BIN forces local backend" "local:$custom_bin" "$result"

echo "--- falls back to docker when local logcli is missing ---"
docker_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" "$docker_dir"' EXIT
cat > "$docker_dir/docker" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$docker_dir/docker"
result="$(PATH="$docker_dir:/usr/bin:/bin" "$BASH_BIN" -c "source '$COMMON'; resolve_logcli_backend; echo \$RESOLVED_LOGCLI_BACKEND:\$RESOLVED_LOGCLI_IMAGE")"
assert_eq "docker fallback is selected" "docker:grafana/logcli:latest" "$result"

echo "--- custom docker image is supported ---"
result="$(LOGCLI_IMAGE="grafana/logcli:main" PATH="$docker_dir:/usr/bin:/bin" "$BASH_BIN" -c "source '$COMMON'; resolve_logcli_backend; echo \$RESOLVED_LOGCLI_IMAGE")"
assert_eq "custom image is kept" "grafana/logcli:main" "$result"

echo "--- invalid LOGCLI_BIN fails clearly ---"
output="$(LOGCLI_BIN="$tmp_dir/missing" PATH="/usr/bin:/bin" "$BASH_BIN" -c "source '$COMMON'; ensure_logcli_backend" 2>&1)" && rc=0 || rc=$?
assert_fail "missing LOGCLI_BIN returns error" "$rc"
assert_contains "missing LOGCLI_BIN error mentions path" "$output" "LOGCLI_BIN is set but not executable"

echo "--- missing local logcli and docker fails clearly ---"
output="$(PATH="/usr/bin:/bin" "$BASH_BIN" -c "source '$COMMON'; ensure_logcli_backend" 2>&1)" && rc=0 || rc=$?
assert_fail "no backend returns error" "$rc"
assert_contains "missing backend error mentions logcli" "$output" "logcli not found in PATH and docker not found"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
