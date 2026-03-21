#!/usr/bin/env bash
set -euo pipefail

# test_env_resolution.sh — validate environment-to-URL resolution

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

echo "--- URL resolution ---"

result="$(LOKI_URL=https://loki.example.test bash -c "source '$COMMON'; resolve_loki_url")" && rc=0 || rc=$?
assert_eq "LOKI_URL resolves from env" "https://loki.example.test" "$result"

result="$(bash -c "source '$COMMON'; resolve_loki_url" 2>/dev/null)" && rc=0 || rc=$?
assert_fail "missing LOKI_URL returns error" "$rc"

echo "--- Chunk size resolution ---"

result="$(LOKI_CHUNK_SECONDS=900 bash -c "source '$COMMON'; resolve_chunk_seconds")"
assert_eq "chunk seconds come from env" "900" "$result"

result="$(bash -c "source '$COMMON'; resolve_chunk_seconds")"
assert_eq "chunk seconds default to 3600s" "3600" "$result"

echo "--- Chunk labels ---"

result="$(LOKI_CHUNK_LABEL=6h bash -c "source '$COMMON'; resolve_chunk_label")"
assert_eq "chunk label comes from env" "6h" "$result"

result="$(LOKI_CHUNK_SECONDS=3600 bash -c "source '$COMMON'; resolve_chunk_label")"
assert_eq "chunk label can be inferred" "1h" "$result"

echo "--- Config resolution (with env var) ---"

result="$(LOKI_URL=https://env-loki.example.test bash -c "source '$COMMON'; resolve_config ''; echo \$RESOLVED_URL:\$RESOLVED_CHUNK_SECONDS")"
assert_eq "resolve_config uses LOKI_URL" "https://env-loki.example.test:3600" "$result"

result="$(LOKI_URL=https://env-loki.example.test bash -c "source '$COMMON'; resolve_config 'https://flag-loki.example.test'; echo \$RESOLVED_URL")"
assert_eq "--url overrides LOKI_URL" "https://flag-loki.example.test" "$result"

echo "--- Runtime does not auto-read .env ---"

ENV_FILE="/Users/Dmytro/Projects/vinitu/logcli-skill/.env"
ENV_BACKUP=""
if [[ -f "$ENV_FILE" ]]; then
  ENV_BACKUP="$(mktemp)"
  cp "$ENV_FILE" "$ENV_BACKUP"
fi

cleanup_env_file() {
  if [[ -n "$ENV_BACKUP" && -f "$ENV_BACKUP" ]]; then
    mv "$ENV_BACKUP" "$ENV_FILE"
  else
    rm -f "$ENV_FILE"
  fi
}

trap 'cleanup_env_file; rm -rf "$tmp_dir"' EXIT

cat > "$ENV_FILE" <<'EOF'
LOKI_URL=https://stage-loki.example.test
LOKI_CHUNK_SECONDS=120
EOF

output="$(bash -c "source '$COMMON'; resolve_config ''" 2>&1)" && rc=0 || rc=$?
assert_fail "runtime ignores bare .env file" "$rc"
assert_eq "error asks for exported LOKI_URL" '{"success":false,"error":"missing exported LOKI_URL. Pass LOKI_URL with the command or use --url."}' "$output"

echo "--- logcli backend labels ---"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
cat > "$tmp_dir/logcli" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_dir/logcli"
result="$(PATH="$tmp_dir:/usr/bin:/bin" "$BASH_BIN" -c "source '$COMMON'; resolve_logcli_backend; logcli_backend_label")"
assert_eq "local backend label is stable" "local" "$result"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
