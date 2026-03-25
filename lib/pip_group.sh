#!/usr/bin/env bash
# lib/pip_group.sh — helper for YAML-driven pip package group targets
# Sourced by components/ai-python-stack.sh

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

# Runner: load all pip group targets from a YAML config file.
# Usage: load_pip_groups_from_yaml <cfg_dir> <yaml_path>
load_pip_groups_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  while IFS=$'\t' read -r grp_name grp_probe grp_pkgs grp_minver; do
    [[ -n "$grp_name" ]] || continue
    _pip_group "$grp_name" "$grp_probe" "$grp_pkgs" "$grp_minver"
  done < <(yaml_records "$cfg_dir" "$yaml" pip_groups name probe packages min_version)
}

# Combined runner for ai-python-stack: pip groups + unsloth studio + MPS note.
# Usage: run_ai_python_stack_from_yaml <cfg_dir> <yaml_path>
run_ai_python_stack_from_yaml() {
  local cfg_dir="$1" yaml="$2"
  load_pip_groups_from_yaml "$cfg_dir" "$yaml"
  register_unsloth_studio_targets "$cfg_dir" "$yaml"
  if [[ "$UCC_DRY_RUN" != "1" ]] && is_installed python3; then
    _MPS_STATUS=$(python3 -c "import torch; print('ok' if torch.backends.mps.is_available() else 'fail')" 2>/dev/null || echo "fail")
    _observe_mps() {
      if [[ "$_MPS_STATUS" == "ok" ]]; then
        ucc_asm_state --installation Configured --runtime Running --health Healthy --admin Enabled --dependencies DepsReady
      else
        ucc_asm_state --installation Configured --runtime Stopped --health Degraded --admin Enabled --dependencies DepsReady
      fi
    }
    _evidence_mps() {
      [[ "$_MPS_STATUS" == "ok" ]] && printf 'gpu=Metal  status=available' || printf 'gpu=Metal  status=unavailable (CPU only)'
    }
    ucc_target_service \
      --name    "mps-available" \
      --observe _observe_mps \
      --evidence _evidence_mps
  fi
}
