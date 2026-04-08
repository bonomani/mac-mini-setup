#!/usr/bin/env bash
# tools/check-bgs.sh — Run the BGS compliance validator against BGS.md.
#
# Usage:
#   tools/check-bgs.sh                  # default: ../BGSPrivate/bgs
#   BGS_REPO=/path/to/bgs tools/check-bgs.sh
#
# Install as a pre-commit hook:
#   ln -sf ../../tools/check-bgs.sh .git/hooks/pre-commit
#
# Exits 0 on PASS or when the validator can't be located (warns, skipped).
# Exits non-zero on validator FAIL so commits/CI block.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BGS_REPO="${BGS_REPO:-$REPO_ROOT/../BGSPrivate/bgs}"
VALIDATOR="$BGS_REPO/tools/check-bgs-compliance.py"
ENTRY="$REPO_ROOT/BGS.md"

if [[ ! -f "$VALIDATOR" ]]; then
  echo "[bgs-check] validator not found at $VALIDATOR — skipped" >&2
  exit 0
fi

if [[ ! -f "$ENTRY" ]]; then
  echo "[bgs-check] BGS.md not found at $ENTRY — skipped" >&2
  exit 0
fi

cd "$REPO_ROOT"
python3 "$VALIDATOR" BGS.md

# Auto-generated docs drift check — fail if SPEC.md or driver-feature-matrix.md
# are out of date relative to source. Cheap (~50ms each), no network.
python3 tools/build-driver-matrix.py --check
python3 tools/build-spec.py --check
