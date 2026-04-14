#!/usr/bin/env bash
# lib/drivers/service.sh — driver.kind: service
# Unified service driver for init-system-managed daemons. Replaces
# brew-service and launchd, both of which share the same observe/action
# shape (presence → running/stopped, start/restart).
#
# custom-daemon and docker-compose-service deliberately stay separate:
# the first is observe-only (no real action) and the second is tightly
# coupled to the ai_apps runner.
#
#  driver.backend: brew | launchd
#
#  brew:
#    driver.ref: <formula-name>
#  launchd:
#    driver.plist:       <launchd label>  (e.g. ai.unsloth.studio)
#    driver.launchd_dir: plist directory relative to $HOME
#                        (default: Library/LaunchAgents)

_service_get_fields() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _SVC_BACKEND="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.backend")"
  _SVC_REF="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.ref")"
  _SVC_PLIST="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.plist")"
  _SVC_LAUNCHD_DIR="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.launchd_dir" 2>/dev/null)"
  _SVC_LAUNCHD_DIR="${_SVC_LAUNCHD_DIR:-Library/LaunchAgents}"
}

_service_launchd_plist_file() {
  printf '%s/%s/%s.plist' "$HOME" "$_SVC_LAUNCHD_DIR" "$_SVC_PLIST"
}

_ucc_driver_service_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _service_get_fields "$cfg_dir" "$yaml" "$target"
  case "$_SVC_BACKEND" in
    brew)
      [[ -n "$_SVC_REF" ]] || return 1
      local pkg_state update_class
      update_class="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "update_class" 2>/dev/null || true)"
      pkg_state="$(brew_observe "$_SVC_REF" "${update_class:-tool}")"
      if [[ "$pkg_state" == "absent" ]]; then
        printf 'absent'; return
      fi
      # outdated formula: trigger update even if service is running
      if [[ "$pkg_state" == "outdated" ]]; then
        printf 'stopped'; return
      fi
      if brew_service_is_started "$_SVC_REF"; then
        printf 'running'
      else
        printf 'stopped'
      fi
      ;;
    launchd)
      [[ -n "$_SVC_PLIST" ]] || return 1
      [[ -f "$(_service_launchd_plist_file)" ]] || { printf 'absent'; return; }
      if launchctl list 2>/dev/null | grep -q "$_SVC_PLIST"; then
        printf 'running'
      else
        printf 'stopped'
      fi
      ;;
    *) return 1 ;;
  esac
}

_ucc_driver_service_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  _service_get_fields "$cfg_dir" "$yaml" "$target"
  case "$_SVC_BACKEND" in
    brew)
      [[ -n "$_SVC_REF" ]] || { log_warn "service[$target]: backend=brew but driver.ref unset"; return 1; }
      case "$action" in
        install)
          ucc_run brew services stop "$_SVC_REF" 2>/dev/null || true
          brew_install "$_SVC_REF" || { log_warn "service[$target]: brew_install '$_SVC_REF' failed"; return 1; }
          ucc_run brew services start "$_SVC_REF" || { log_warn "service[$target]: brew services start '$_SVC_REF' failed"; return 1; }
          ;;
        update)
          ucc_run brew services stop "$_SVC_REF" 2>/dev/null || true
          brew_upgrade "$_SVC_REF" || { log_warn "service[$target]: brew_upgrade '$_SVC_REF' failed"; return 1; }
          ucc_run brew services start "$_SVC_REF" || { log_warn "service[$target]: brew services start '$_SVC_REF' failed"; return 1; }
          ;;
      esac
      ;;
    launchd)
      [[ -n "$_SVC_PLIST" ]] || { log_warn "service[$target]: backend=launchd but driver.plist unset"; return 1; }
      local file; file="$(_service_launchd_plist_file)"
      case "$action" in
        install) ucc_run launchctl load "$file" || { log_warn "service[$target]: launchctl load '$file' failed"; return 1; } ;;
        update)
          ucc_run launchctl unload "$file" 2>/dev/null || true
          ucc_run launchctl load "$file" || { log_warn "service[$target]: launchctl load '$file' failed"; return 1; }
          ;;
      esac
      ;;
    *) log_warn "service[$target]: unknown backend '$_SVC_BACKEND'"; return 1 ;;
  esac
}

_ucc_driver_service_recover() {
  local cfg_dir="$1" yaml="$2" target="$3" level="$4"
  _service_get_fields "$cfg_dir" "$yaml" "$target"
  case "$_SVC_BACKEND" in
    brew)
      [[ -n "$_SVC_REF" ]] || return 1
      case "$level" in
        1) # Retry: just restart the service
          ucc_run brew services stop "$_SVC_REF" 2>/dev/null || true
          ucc_run brew services start "$_SVC_REF"
          ;;
        2) # Reinstall: uninstall + install + start
          ucc_run brew services stop "$_SVC_REF" 2>/dev/null || true
          ucc_run brew uninstall "$_SVC_REF" 2>/dev/null || true
          brew_install "$_SVC_REF"
          ucc_run brew services start "$_SVC_REF"
          ;;
        3) # Clean: untap + retap + install + start
          ucc_run brew services stop "$_SVC_REF" 2>/dev/null || true
          ucc_run brew uninstall "$_SVC_REF" 2>/dev/null || true
          local tap="${_SVC_REF%/*}"
          if [[ "$tap" == */* ]]; then
            ucc_run brew untap "$tap" 2>/dev/null || true
            ucc_run brew tap "$tap"
          fi
          brew_install "$_SVC_REF"
          ucc_run brew services start "$_SVC_REF"
          ;;
        *) return 2 ;;  # level not supported
      esac
      ;;
    launchd)
      [[ -n "$_SVC_PLIST" ]] || return 1
      local file; file="$(_service_launchd_plist_file)"
      case "$level" in
        1) # Retry: unload + load
          ucc_run launchctl unload "$file" 2>/dev/null || true
          ucc_run launchctl load "$file"
          ;;
        *) return 2 ;;  # level not supported
      esac
      ;;
    *) return 2 ;;  # backend not supported
  esac
}

_ucc_driver_service_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  _service_get_fields "$cfg_dir" "$yaml" "$target"
  case "$_SVC_BACKEND" in
    brew)
      [[ -n "$_SVC_REF" ]] || return 1
      local ver out
      ver="$(_brew_cached_version "$_SVC_REF")"
      [[ -n "$ver" ]] && out="version=$ver"
      # Conventional brew services log location
      local prefix log short_ref="${_SVC_REF##*/}"
      prefix="$(brew --prefix 2>/dev/null)"
      if [[ -n "$prefix" ]]; then
        for log in "$prefix/var/log/${short_ref}.log" "$HOME/Library/Logs/${short_ref}.log"; do
          if [[ -f "$log" ]]; then
            out="${out:+$out  }log=$log"
            break
          fi
        done
      fi
      [[ -n "$out" ]] && printf '%s' "$out"
      ;;
    launchd)
      [[ -n "$_SVC_PLIST" ]] || return 1
      local plist_file log_path
      plist_file="$(_service_launchd_plist_file)"
      printf 'plist=%s' "$plist_file"
      # Read StandardOutPath / StandardErrorPath if defined
      if [[ -f "$plist_file" ]] && command -v plutil >/dev/null 2>&1; then
        log_path="$(plutil -extract StandardOutPath raw -- "$plist_file" 2>/dev/null \
          || plutil -extract StandardErrorPath raw -- "$plist_file" 2>/dev/null || true)"
        [[ -n "$log_path" ]] && printf '  log=%s' "$log_path"
      fi
      ;;
  esac
}
