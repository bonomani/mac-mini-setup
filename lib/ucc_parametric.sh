#!/usr/bin/env bash
# lib/ucc_parametric.sh — small helpers for parametric (value-convergence)
# targets that apply a *dynamic* JSON patch to a settings file.
#
# Static-patch JSON files are already covered by `driver.kind: json-merge`
# (lib/drivers/vscode.sh). This helper exists for callers whose patch
# content is computed at observe time from prefs/YAML and can't be a
# checked-in patch file.
#
# Usage:
#   _ucc_parametric_apply_json_patch <settings_path> <patch_basename> <patch_json>
#
# Writes <patch_json> to "$CFG_DIR/.build/<patch_basename>" and applies it
# to <settings_path> via tools/drivers/json_merge.py. Returns the json_merge
# tool's exit code. The caller is responsible for ensuring <settings_path>
# exists; this helper does not create it.

_ucc_parametric_apply_json_patch() {
  local settings_path="$1" patch_basename="$2" patch_json="$3"
  [[ -n "$settings_path" && -n "$patch_basename" && -n "$patch_json" ]] || {
    log_warn "_ucc_parametric_apply_json_patch: settings_path/patch_basename/patch_json all required"
    return 2
  }
  local patch_dir="$CFG_DIR/.build"
  local patch_path="$patch_dir/$patch_basename"
  mkdir -p "$patch_dir"
  printf '%s\n' "$patch_json" > "$patch_path"
  ucc_run python3 "$CFG_DIR/tools/drivers/json_merge.py" apply "$settings_path" "$patch_path"
}

# Read a single scalar from a JSON file. Prints `default` when the file
# does not exist or the key is missing/null. Key uses dot-path notation
# (e.g. "memoryMiB", "advanced.cpu_count"). Numbers/strings/bools are
# stringified with str(); the caller decides interpretation.
#
# Usage:
#   _ucc_parametric_json_field <path> <key> [default]
_ucc_parametric_json_field() {
  local path="$1" key="$2" default="${3:-}"
  if [[ ! -f "$path" ]]; then
    printf '%s' "$default"; return 0
  fi
  python3 - "$path" "$key" "$default" <<'PY' 2>/dev/null || printf '%s' "$default"
import json, sys
path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        d = json.load(f)
    for part in key.split('.'):
        d = d[part]
    if d is None:
        sys.stdout.write(default)
    else:
        sys.stdout.write(str(d))
except (KeyError, TypeError, ValueError, OSError):
    sys.stdout.write(default)
PY
}
