#!/usr/bin/env bash
# Starts a packaged hnsd wrapper on spare ports and waits until it resolves a
# Handshake name and an ICANN name through its recursive resolver.
# Usage: smoke-test.sh <path to packaged "hnsd" wrapper> [timeout seconds]
set -euo pipefail
WRAPPER=$1
TIMEOUT=${2:-600}
export HOME
HOME=$(mktemp -d)
export XDG_DATA_HOME="$HOME/.local/share"
LOG="$HOME/hnsd.log"

"$WRAPPER" --ns-host 127.0.0.1:25391 --rs-host 127.0.0.1:25392 --pool-size 4 >"$LOG" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT

resolves() { # name -> succeeds if the recursive resolver returns an A record
  dig +time=3 +tries=1 @127.0.0.1 -p 25392 "$1" A | grep -qE "^$1\.\s+[0-9]+\s+IN\s+A\s"
}

start=$(date +%s)
until resolves woodburn && resolves example.com; do
  if ! kill -0 $PID 2>/dev/null; then
    echo "FAIL: hnsd exited"; tail -30 "$LOG"; exit 1
  fi
  if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
    echo "FAIL: no resolution after ${TIMEOUT}s"; grep -E '^chain \(' "$LOG" | tail -3; tail -10 "$LOG"; exit 1
  fi
  sleep 5
done
echo "OK: resolved woodburn and example.com after $(( $(date +%s) - start ))s"
grep -m1 'fully synced' "$LOG" || true
# Headers must persist in the per-user data dir, not next to the binary.
store=$(find "$HOME" -path '*Fingertip-dit/hnsd-data*' -type f | head -1)
if [ -z "$store" ]; then echo "FAIL: no header store in per-user data dir"; exit 1; fi
echo "OK: header store at ${store#$HOME/}"
