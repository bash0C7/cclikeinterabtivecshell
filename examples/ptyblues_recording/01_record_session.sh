#!/usr/bin/env bash
# Record a baslash echo_shell session via the ttyblues hub.
# Demonstrates the write-side workflow: serve → start → input → wait → stop.
# `ttyblues start` auto-generates the 8-char session short id from a UUID; we
# parse it out of the start output and hand it down the rest of the pipeline.
# Run from the baslash repo root.

set -euo pipefail

# Pre-create the session_dir that the record-daemon will bind its UNIX socket
# in. Without this, `ttyblues start` fails with Errno::ENOENT inside the
# per-session record daemon (it tries to bind tmp/ptyblues/<short>.record.sock
# without first ensuring the parent dir exists).
mkdir -p tmp tmp/ptyblues

echo "==> Ensuring ttyblues hub is up"
bundle exec ttyblues serve --detach || true

echo "==> Starting baslash echo_shell under PTY recording"
START_OUT=$(bundle exec ttyblues start -- bundle exec ruby examples/echo_shell.rb)
echo "$START_OUT"

SHORT=$(printf '%s\n' "$START_OUT" | sed -n 's/^started session=\([0-9a-f]\{8\}\).*/\1/p')
if [ -z "$SHORT" ]; then
  echo "ERROR: could not parse session id from 'ttyblues start' output" >&2
  exit 1
fi
echo "$SHORT" > tmp/.last_session
echo "==> session=$SHORT (saved to tmp/.last_session)"

sleep 0.5
echo "==> Sending /slow to exercise the live-slot demo"
bundle exec ttyblues input "$SHORT" $'/slow\r'

sleep 1.5
echo "==> Capturing a framework-state snapshot (so 'ttyblues frames' has rows)"
bundle exec ttyblues capture "$SHORT" --event-kind slow_done

echo "==> Sending EOF to end the session (echo_shell exits on stdin close)"
bundle exec ttyblues input "$SHORT" $'\x04'

echo "==> Waiting up to 5s for the child to exit"
bundle exec ttyblues wait "$SHORT" --timeout 5 || true

echo "==> Stopping the per-session record daemon"
bundle exec ttyblues stop "$SHORT"

echo "==> Done. Run 02_inspect_session.sh to inspect."
