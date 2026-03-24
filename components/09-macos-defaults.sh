#!/usr/bin/env bash
# Component: macOS system defaults (optimized for AI workloads)
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pmset + defaults write settings)
#       Axis B = Basic
# Boundary: macOS system preferences API · pmset (requires sudo)
# Note: com.apple.universalaccess reduce transparency is write-protected on macOS 14+.
#       Set manually in System Settings if needed.

DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$DIR/lib/macos_defaults.sh"
run_macos_defaults_from_yaml "$DIR" "$DIR/config/09-macos-defaults.yaml"
ucc_summary "09-macos-defaults"
