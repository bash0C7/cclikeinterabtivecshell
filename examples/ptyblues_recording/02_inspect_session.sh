#!/usr/bin/env bash
# Inspect the session recorded by 01_record_session.sh.
# Demonstrates the read-side workflow: list → info → frames → semantic → export.
# Session id comes from $1, falling back to tmp/.last_session (written by 01).
# Run from the baslash repo root.

set -euo pipefail

SHORT="${1:-$(cat tmp/.last_session 2>/dev/null || true)}"
if [ -z "$SHORT" ]; then
  echo "ERROR: pass session id as arg, or run 01_record_session.sh first" >&2
  exit 1
fi
mkdir -p tmp

echo "==> All recorded sessions:"
bundle exec ptyblues list

echo "==> Session info for $SHORT:"
bundle exec ptyblues info "$SHORT"

echo "==> Frames (first 10):"
bundle exec ptyblues frames "$SHORT" | head -10

echo "==> Semantic search for 'done' (top 3):"
bundle exec ptyblues semantic "$SHORT" "done" -k 3 || \
  echo "    (semantic search may be empty if the embedder backfill has not run)"

echo "==> Exporting to asciinema cast at tmp/$SHORT.cast:"
bundle exec ptyblues export "$SHORT" --format cast --output "tmp/$SHORT.cast"

echo "==> Done. Open tmp/$SHORT.cast with asciinema play."
