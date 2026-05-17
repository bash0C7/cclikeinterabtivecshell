#!/usr/bin/env bash
# Record a baslash echo_shell session via the ttyblues hub.
# Demonstrates the write-side workflow: serve → start → input → wait → stop.
# Run from the baslash repo root.

set -euo pipefail

SHORT="example1"

echo "==> Ensuring ttyblues hub is up"
bundle exec ttyblues serve --detach || true

echo "==> Starting baslash echo_shell under PTY recording (short=$SHORT)"
bundle exec ttyblues start --short "$SHORT" -- bundle exec ruby examples/echo_shell.rb

sleep 0.5
echo "==> Sending /slow to exercise the live-slot demo"
bundle exec ttyblues input "$SHORT" $'/slow\r'

sleep 1.5
echo "==> Sending EOF to end the session (echo_shell exits on stdin close)"
bundle exec ttyblues input "$SHORT" $'\x04'

echo "==> Waiting up to 5s for the child to exit"
bundle exec ttyblues wait "$SHORT" --timeout 5 || true

echo "==> Stopping the per-session record daemon"
bundle exec ttyblues stop "$SHORT"

echo "==> Done. Run 02_inspect_session.sh to inspect."
