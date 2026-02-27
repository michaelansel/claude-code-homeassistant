#!/usr/bin/env bash
# Test claude-watcher.py against the mock coordinator.
# Runs entirely locally — no HA instance needed.
#
# Usage:
#   ./tests/test_watcher.sh
#
# What it does:
#   1. Starts mock_coordinator.py on localhost:9420
#   2. Writes a temp credentials file pointing to the mock
#   3. Runs claude-watcher.py (with --session-dir /tmp so it won't try to exec claude)
#   4. The mock triggers after 3 polls; watcher will attempt to launch a session
#      (which will fail since 'claude' isn't configured, but that's fine — we're
#       testing the protocol, not the session)
#   5. After 15s, kills both processes and reports pass/fail

set -euo pipefail
cd "$(dirname "$0")/.."

PORT=9420
MOCK_PID=""
WATCHER_PID=""
TMPDIR_TEST=$(mktemp -d)
CREDS_FILE="$TMPDIR_TEST/creds.json"
SESSION_DIR="$TMPDIR_TEST/sessions"
MOCK_LOG="$TMPDIR_TEST/mock.log"
WATCHER_LOG="$TMPDIR_TEST/watcher.log"

cleanup() {
    [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
    [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Watcher protocol test ==="
echo "Temp dir: $TMPDIR_TEST"

# Write credentials pointing to mock
cat > "$CREDS_FILE" <<EOF
{
  "coordinator_url": "http://127.0.0.1:${PORT}",
  "api_token": "test-token"
}
EOF

mkdir -p "$SESSION_DIR"

# Start mock coordinator
python3 tests/mock_coordinator.py --port "$PORT" --trigger-after 3 > "$MOCK_LOG" 2>&1 &
MOCK_PID=$!
sleep 0.5  # let it bind

# Start watcher (no real claude needed — session will fail gracefully)
# Unset CLAUDECODE so claude can run if present (normally blocked inside Claude Code sessions)
C3PO_MACHINE_NAME=haos \
C3PO_PROJECT_NAME=homeassistant \
PYTHONUNBUFFERED=1 \
CLAUDECODE="" \
    python3 rootfs/usr/local/bin/claude-watcher.py \
        --creds-file "$CREDS_FILE" \
        --work-dir "$TMPDIR_TEST" \
        --session-dir "$SESSION_DIR" \
        --max-sessions 5 \
    > "$WATCHER_LOG" 2>&1 &
WATCHER_PID=$!

# Wait for watcher to go through a few cycles
echo "Running for 15s..."
sleep 15

kill "$WATCHER_PID" 2>/dev/null || true
kill "$MOCK_PID" 2>/dev/null || true
wait "$WATCHER_PID" 2>/dev/null || true
wait "$MOCK_PID" 2>/dev/null || true
WATCHER_PID=""
MOCK_PID=""

echo ""
echo "=== Mock coordinator log ==="
cat "$MOCK_LOG"

echo ""
echo "=== Watcher log ==="
cat "$WATCHER_LOG"

echo ""
echo "=== Analysis ==="

PASS=true

# Check: watcher registered
if grep -q "Registered as 'haos/homeassistant'" "$WATCHER_LOG"; then
    echo "✓ Registered with correct agent ID"
else
    echo "✗ Did not register correctly"
    PASS=false
fi

# Check: watcher entered watching state
if grep -q "Watching state set for 'haos/homeassistant'" "$WATCHER_LOG"; then
    echo "✓ Entered watching state"
else
    echo "✗ Did not enter watching state"
    PASS=false
fi

# Check: watcher polled wait
if grep -q "X-Machine-Name='haos/homeassistant'" "$MOCK_LOG"; then
    echo "✓ Wait polls include correct X-Machine-Name header"
else
    echo "✗ Wait polls missing or wrong X-Machine-Name"
    PASS=false
fi

# Check: no protocol errors in mock
if grep -q "ERRORS DETECTED" "$MOCK_LOG"; then
    echo "✗ Protocol errors detected (see mock log above)"
    PASS=false
else
    echo "✓ No protocol errors"
fi

# Check: watcher attempted session launch after trigger
if grep -q "Message received, launching session" "$WATCHER_LOG"; then
    echo "✓ Watcher triggered session launch on message"
else
    echo "✗ Watcher did not launch session (may not have reached trigger yet)"
    PASS=false
fi

echo ""
if $PASS; then
    echo "PASS"
    exit 0
else
    echo "FAIL"
    exit 1
fi
