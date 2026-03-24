#!/usr/bin/env bash
# Component: macOS system defaults (optimized for AI workloads)
# BGS: UCC + Basic
#
# BISS: Axis A = UCC (state convergence — pmset + defaults write settings)
#       Axis B = Basic
# Boundary: macOS system preferences API · pmset (requires sudo)
#
# Note: com.apple.universalaccess reduce transparency is write-protected on macOS 14+ from scripts.
# Set manually in System Settings if needed.

_MD_CFG_DIR="${DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
_MD_CFG="$_MD_CFG_DIR/config/09-macos-defaults.yaml"

source "$_MD_CFG_DIR/lib/macos_defaults.sh"

while IFS=$'\t' read -r md_name md_desired md_read md_apply; do
  [[ -n "$md_name" ]] || continue
  _macos_defaults_target "$md_name" "$md_read" "$md_desired" "$md_apply"
done < <(python3 "$_MD_CFG_DIR/tools/read_config.py" --records \
    "$_MD_CFG" defaults name desired read apply 2>/dev/null)

if [[ "$UCC_DRY_RUN" != "1" && $_UCC_CHANGED -gt 0 ]]; then
  while IFS= read -r _proc; do
    [[ -n "$_proc" ]] && { killall "$_proc" 2>/dev/null || true; }
  done < <(python3 "$_MD_CFG_DIR/tools/read_config.py" --list "$_MD_CFG" restart_processes 2>/dev/null)
  log_info "Finder/Dock/SystemUIServer restarted"
fi

ucc_summary "09-macos-defaults"
