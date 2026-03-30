#!/usr/bin/env bash
# lib/drivers/app_bundle.sh — driver.kind: app-bundle
# driver.app_path:          <full-path>       (e.g., /Applications/Visual Studio Code.app)
# driver.brew_cask:         <cask-name>       (optional) if set: delegate to brew when cask is installed,
#                                             warn when cask is available but not installed
# driver.update_api:        <api-endpoint>    (e.g., https://update.code.visualstudio.com/api/releases/stable)
# driver.download_url_tpl:  <url-template>    ({version} placeholder, e.g., https://example.com/{version}/app.zip)
# driver.package_ext:       zip|dmg           (default: zip)

_ucc_driver_app_bundle_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local app_path brew_cask ver
  app_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.app_path")"
  [[ -n "$app_path" ]] || return 1
  brew_cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.brew_cask")"

  # If cask is already installed via brew, delegate entirely — it is brew-managed now
  if [[ -n "$brew_cask" ]] && [[ -n "$(_brew_cask_cached_version "$brew_cask")" ]]; then
    brew_cask_observe "$brew_cask"
    return
  fi

  [[ -d "$app_path" ]] || { printf 'absent'; return; }

  # App exists but not brew-managed: warn once if cask is available in the brew tap
  if [[ -n "$brew_cask" ]]; then
    log_warn "app-bundle '$target': '${app_path##*/}' is available as brew cask '$brew_cask' — consider migrating (driver.kind: brew-cask)"
  fi

  ver="$(defaults read "$app_path/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
  printf '%s' "${ver:-installed}"
}

_ucc_driver_app_bundle_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local app_path brew_cask update_api download_url_tpl pkg_ext
  app_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.app_path")"
  brew_cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.brew_cask")"
  [[ -n "$app_path" ]] || return 1

  # If cask is already installed via brew, delegate to brew
  if [[ -n "$brew_cask" ]] && [[ -n "$(_brew_cask_cached_version "$brew_cask")" ]]; then
    case "$action" in
      install) brew_cask_install "$brew_cask" ;;
      update)  brew_cask_upgrade "$brew_cask" ;;
    esac
    return
  fi

  # Cask available but not installed: warn and proceed with direct download
  if [[ -n "$brew_cask" ]]; then
    log_warn "app-bundle '$target': brew cask '$brew_cask' is available — run 'brew install --cask $brew_cask' to migrate to brew management"
  fi

  update_api="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.update_api")"
  download_url_tpl="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.download_url_tpl")"
  pkg_ext="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package_ext")"
  [[ -n "$update_api" && -n "$download_url_tpl" ]] || return 1
  [[ -n "$pkg_ext" ]] || pkg_ext="zip"

  # Fetch latest version from API (JSON array or newline-separated)
  local latest response
  response="$(curl -sL --max-time 30 "$update_api" 2>/dev/null)" || return 1
  latest="$(printf '%s' "$response" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
  [[ -n "$latest" ]] || return 1

  local download_url pkg_file tmp_dir
  download_url="${download_url_tpl//\{version\}/$latest}"
  tmp_dir="$(mktemp -d)"
  pkg_file="$tmp_dir/update.$pkg_ext"

  ucc_run curl -sL --max-time 300 -o "$pkg_file" "$download_url" || { rm -rf "$tmp_dir"; return 1; }

  case "$pkg_ext" in
    dmg)
      local mount_point
      mount_point="$(hdiutil attach "$pkg_file" -nobrowse -readonly 2>/dev/null \
        | awk '/\/Volumes\//{print $NF}' | head -1)"
      if [[ -z "$mount_point" ]]; then rm -rf "$tmp_dir"; return 1; fi
      local src_app
      src_app="$(find "$mount_point" -maxdepth 1 -name "*.app" -type d | head -1)"
      if [[ -n "$src_app" ]]; then
        ucc_run cp -R "$src_app" /Applications/
      fi
      hdiutil detach "$mount_point" -quiet 2>/dev/null || true
      [[ -n "$src_app" ]] || { rm -rf "$tmp_dir"; return 1; }
      ;;
    zip)
      ucc_run unzip -q -o "$pkg_file" -d "$tmp_dir/extract" || { rm -rf "$tmp_dir"; return 1; }
      local src_app
      src_app="$(find "$tmp_dir/extract" -maxdepth 2 -name "*.app" -type d | head -1)"
      if [[ -n "$src_app" ]]; then
        ucc_run cp -R "$src_app" /Applications/
      fi
      [[ -n "$src_app" ]] || { rm -rf "$tmp_dir"; return 1; }
      ;;
    *)
      rm -rf "$tmp_dir"; return 1 ;;
  esac

  rm -rf "$tmp_dir"
}

_ucc_driver_app_bundle_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local app_path brew_cask ver
  app_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.app_path")"
  [[ -n "$app_path" && -d "$app_path" ]] || return 1
  brew_cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.brew_cask")"

  # If brew-managed, report cask version (may differ from plist version)
  if [[ -n "$brew_cask" ]] && [[ -n "$(_brew_cask_cached_version "$brew_cask")" ]]; then
    local cask_ver
    cask_ver="$(_brew_cask_cached_version "$brew_cask")"
    printf 'version=%s  managed=brew-cask  path=%s' "$cask_ver" "$app_path"
    return
  fi

  ver="$(defaults read "$app_path/Contents/Info" CFBundleShortVersionString 2>/dev/null)"
  [[ -n "$ver" ]] || return 1
  printf 'version=%s  path=%s' "$ver" "$app_path"
}
