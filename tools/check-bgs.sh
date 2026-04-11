#!/usr/bin/env bash
# tools/check-bgs.sh — Run BGS compliance + auto-generated-docs drift check.
#
# Works both as a direct invocation from the repo and as a pre-commit hook
# installed at an arbitrary path (e.g. ~/.git-hooks/pre-commit via a symlink).
# REPO_ROOT is derived from `git rev-parse --show-toplevel` so we never
# depend on `$0`'s resolved location.
#
# Usage (direct):
#   tools/check-bgs.sh
#   BGS_REPO=/path/to/bgs tools/check-bgs.sh
#
# Install as a pre-commit hook (GLOBAL, all repos — the script is
# inert in repos that don't carry tools/build-driver-matrix.py):
#   ln -sf "$(pwd)/tools/check-bgs.sh" ~/.git-hooks/pre-commit
#
# Exit codes:
#   0 — PASS, or inert (not in a repo / not this repo / BGS validator absent)
#   non-zero — BGS validator FAIL or doc drift detected

set -eu

# Use git to find the current repo root regardless of how the script is
# invoked (direct, symlink, hook). Falls back to the script's own parent if
# git can't find a repo — in that case we're not in a tracked checkout and
# should just exit 0.
if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  echo "[bgs-check] not inside a git repo — skipped" >&2
  exit 0
fi

# Inert guard: if this repo does not carry the auto-generated doc tooling,
# the script is not meant to run here (e.g., the hook is installed globally
# but the user is committing in an unrelated repo). Exit 0 so the commit
# proceeds in that repo.
if [[ ! -f "$REPO_ROOT/tools/build-driver-matrix.py" ]]; then
  exit 0
fi

BGS_REPO="${BGS_REPO:-$REPO_ROOT/../BGSPrivate/bgs}"
VALIDATOR="$BGS_REPO/tools/check-bgs-compliance.py"
ENTRY="$REPO_ROOT/BGS.md"

cd "$REPO_ROOT"

if [[ ! -f "$VALIDATOR" ]]; then
  echo "[bgs-check] BGS validator not found at $VALIDATOR — BGS check skipped" >&2
elif [[ ! -f "$ENTRY" ]]; then
  echo "[bgs-check] BGS.md not found at $ENTRY — BGS check skipped" >&2
else
  python3 "$VALIDATOR" BGS.md
fi

# Auto-generated docs drift check — fail if SPEC.md or driver-feature-matrix.md
# are out of date relative to source. Cheap (~50ms each), no network. These
# run unconditionally whenever this script is invoked inside a mac-mini-setup
# checkout.
python3 tools/build-driver-matrix.py --check
python3 tools/build-spec.py --check
