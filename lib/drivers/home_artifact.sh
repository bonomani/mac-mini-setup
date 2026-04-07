#!/usr/bin/env bash
# lib/drivers/home_artifact.sh — driver.kind: home-artifact
# Single driver for filesystem artifacts written under $HOME.
#
#  driver.subkind: script | symlink
#
# subkind=script  (replaces former bin-script driver)
#   driver.script_name: name of the file under $CFG_DIR/scripts/
#   driver.bin_dir:     relative path from $HOME to install into
#
# subkind=symlink (replaces former cli-symlink driver)
#   driver.src_path:     absolute path to source binary
#   driver.link_relpath: relative path from $HOME for the symlink
#   driver.cmd:          command name (oracle/evidence)
#   driver.hint:         optional warning shown after install

_ucc_driver_home_artifact_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local subkind; subkind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.subkind")"
  case "$subkind" in
    script)
      local script_name bin_dir
      script_name="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.script_name")"
      bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
      [[ -n "$script_name" && -n "$bin_dir" ]] || return 1
      [[ -x "$HOME/$bin_dir/$script_name" ]] && printf 'installed' || printf 'absent'
      ;;
    symlink)
      local cmd; cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cmd")"
      [[ -n "$cmd" ]] || return 1
      command -v "$cmd" >/dev/null 2>&1 && printf 'installed' || printf 'absent'
      ;;
    *) return 1 ;;
  esac
}

_ucc_driver_home_artifact_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local subkind; subkind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.subkind")"
  case "$subkind" in
    script)
      local script_name bin_dir
      script_name="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.script_name")"
      bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
      [[ -n "$script_name" && -n "$bin_dir" ]] || return 1
      mkdir -p "$HOME/$bin_dir"
      install -m 755 "$cfg_dir/scripts/$script_name" "$HOME/$bin_dir/$script_name"
      ;;
    symlink)
      local src_path link_relpath hint
      src_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.src_path")"
      link_relpath="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.link_relpath")"
      hint="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.hint")"
      [[ -n "$src_path" && -n "$link_relpath" ]] || return 1
      if [[ -x "$src_path" ]]; then
        mkdir -p "$(dirname "$HOME/${link_relpath}")"
        ln -sf "$src_path" "$HOME/${link_relpath}"
        export PATH="$(dirname "$HOME/${link_relpath}"):$PATH"
        [[ -n "$hint" ]] && log_warn "$hint"
      else
        log_warn "Source binary not found at '${src_path}'. Install the app first."
        return 1
      fi
      ;;
    *) return 1 ;;
  esac
}

_ucc_driver_home_artifact_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local subkind; subkind="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.subkind")"
  case "$subkind" in
    script)
      local script_name bin_dir file md5=""
      script_name="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.script_name")"
      bin_dir="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.bin_dir")"
      [[ -n "$script_name" && -n "$bin_dir" ]] || return 1
      file="$HOME/$bin_dir/$script_name"
      if [[ -f "$file" ]]; then
        md5="$(md5sum "$file" 2>/dev/null | awk '{print substr($1,1,8)}' || md5 -q "$file" 2>/dev/null | cut -c1-8)"
      fi
      printf 'path=%s' "$file"
      [[ -n "$md5" ]] && printf '  md5=%s' "$md5"
      ;;
    symlink)
      local cmd ver path
      cmd="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.cmd")"
      [[ -n "$cmd" ]] || return 1
      ver="$("$cmd" --version 2>/dev/null | head -1)"
      path="$(command -v "$cmd" 2>/dev/null || true)"
      [[ -n "$path" ]] && printf 'version=%s  path=%s' "${ver:-?}" "$path"
      ;;
  esac
}
