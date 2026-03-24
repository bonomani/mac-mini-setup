#!/usr/bin/env bash
# lib/pip_group.sh — helper for YAML-driven pip package group targets
# Sourced by components/06-ai-python-stack.sh

# Helper: define one pip group as a ucc_target
# Usage: _pip_group <name> <probe_pkg> "<space-separated packages>" [<min_version>]
# When min_version is set, the observe uses importlib.metadata + packaging.version
# to enforce a minimum version of the probe package (triggers upgrade if below).
_pip_group() {
  local name="$1" first="$2" pkgs="$3" minver="${4:-}"
  local fn="${name//[^a-zA-Z0-9]/_}"

  if [[ -n "$minver" ]]; then
    eval "_observe_grp_${fn}() {
      local raw
      raw=\$(python3 -c \"
import sys
try:
    import importlib.metadata
    ver = importlib.metadata.version('${first}')
    from packaging.version import Version
    sys.exit(0 if Version(ver) >= Version('${minver}') else 1)
except Exception:
    sys.exit(1)
\" 2>/dev/null && pip show '${first}' 2>/dev/null | awk '/^Version:/ {print \$2}' || echo 'absent')
      ucc_asm_package_state \"\$raw\"
    }"
  else
    eval "_observe_grp_${fn}() { local raw; raw=\$(pip_is_installed '${first}' && pip show '${first}' 2>/dev/null | awk '/^Version:/ {print \$2}' || echo 'absent'); ucc_asm_package_state \"\$raw\"; }"
  fi
  eval "_evidence_grp_${fn}() { local ver; ver=\$(pip show '${first}' 2>/dev/null | awk '/^Version:/ {print \$2}'); [[ -n \"\$ver\" ]] && printf 'version=%s pkg=${first}' \"\$ver\"; }"
  eval "_install_grp_${fn}() { ucc_run pip install -q ${pkgs}; }"
  eval "_update_grp_${fn}()  { ucc_run pip install -q --upgrade ${pkgs}; }"

  ucc_target_nonruntime \
    --name    "pip-group-$name" \
    --observe "_observe_grp_${fn}" \
    --evidence "_evidence_grp_${fn}" \
    --install "_install_grp_${fn}" \
    --update  "_update_grp_${fn}"
}
