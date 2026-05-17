#!/usr/bin/env bash
# Inspect the session recorded by 01_record_session.sh.
# Demonstrates the read-side workflow: list → info → frames → semantic → export.
# Run from the baslash repo root.

set -euo pipefail

SHORT="example1"
mkdir -p tmp

echo "==> All recorded sessions:"
bundle exec ttyblues list

echo "==> Session info for $SHORT:"
bundle exec ttyblues info "$SHORT"

echo "==> First 10 frames:"
bundle exec ttyblues frames "$SHORT" --limit 10

echo "==> Semantic search for 'done' (top 3):"
bundle exec ttyblues semantic "$SHORT" "done" --k 3 || \
  echo "    (semantic search may be empty if the embedder backfill has not run)"

echo "==> Exporting to asciinema cast at tmp/$SHORT.cast:"
bundle exec ttyblues export "$SHORT" --format cast --output "tmp/$SHORT.cast"

echo "==> Done. Open tmp/$SHORT.cast with asciinema play."
