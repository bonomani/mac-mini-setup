#!/usr/bin/env bash
# lib/drivers/app_bundle.sh — driver.kind: app-bundle
# driver.app_path:          <full-path>       (e.g., /Applications/Visual Studio Code.app)
# driver.brew_cask:         <cask-name>       (optional) if set: delegate to brew when cask is installed,
#                                             warn when cask is available but not installed
# driver.update_api:        <api-endpoint>    (e.g., https://update.code.visualstudio.com/api/releases/stable)
# driver.download_url_tpl:  <url-template>    ({version} placeholder, e.g., https://example.com/{version}/app.zip)
# driver.package_ext:       zip|dmg           (default: zip)

_app_bundle_plist_version() {
  defaults read "$1/Contents/Info" CFBundleShortVersionString 2>/dev/null
}

_ucc_driver_app_bundle_observe() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local app_path brew_cask ver cask_ver
  app_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.app_path")"
  log_debug "app-bundle[$target] observe: app_path='$app_path'"
  [[ -n "$app_path" ]] || return 1
  brew_cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.brew_cask")"
  log_debug "app-bundle[$target] observe: brew_cask='${brew_cask:-<none>}'"

  # brew-cask is the preferred driver; app-bundle is a fallback for unmanaged installs
  if [[ -n "$brew_cask" ]]; then
    cask_ver="$(_brew_cask_cached_version "$brew_cask")"
    log_debug "app-bundle[$target] observe: brew cask cached version='${cask_ver:-<not installed>}'"
    if [[ -n "$cask_ver" ]]; then
      log_warn "app-bundle '$target': managed by brew cask '$brew_cask' — preferred driver is brew-cask; change driver.kind to brew-cask in YAML"
      log_debug "app-bundle[$target] observe: delegating to brew_cask_observe '$brew_cask'"
      brew_cask_observe "$brew_cask"
      return
    fi
    # Cask not yet brew-installed but available: recommend it
    log_warn "app-bundle '$target': brew cask '$brew_cask' is available — preferred driver is brew-cask; run 'brew install --cask $brew_cask' then change driver.kind to brew-cask in YAML"
  fi

  if [[ ! -d "$app_path" ]]; then
    log_debug "app-bundle[$target] observe: app not found at '$app_path' → absent"
    printf 'absent'
    return
  fi

  ver="$(_app_bundle_plist_version "$app_path")"
  log_debug "app-bundle[$target] observe: plist version='${ver:-<unreadable>}'"

  # Compare against latest from API to detect outdated
  local update_api latest response
  update_api="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.update_api")"
  if [[ -n "$update_api" && -n "$ver" ]]; then
    log_debug "app-bundle[$target] observe: fetching latest version from '$update_api'"
    response="$(curl -sL --max-time "$(_ucc_curl_timeout metadata)" "$update_api" 2>/dev/null)"
    latest="$(printf '%s' "$response" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    log_debug "app-bundle[$target] observe: latest='${latest:-<parse failed>}' current='$ver'"
    if [[ -n "$latest" && "$latest" != "$ver" ]]; then
      local oldest
      oldest="$(printf '%s\n%s' "$ver" "$latest" | sort -V | head -1)"
      if [[ "$oldest" == "$ver" ]]; then
        log_debug "app-bundle[$target] observe: '$ver' < '$latest' → outdated"
        printf 'outdated'
        return
      fi
    fi
  fi

  printf '%s' "${ver:-installed}"
}

_ucc_driver_app_bundle_action() {
  local cfg_dir="$1" yaml="$2" target="$3" action="$4"
  local app_path brew_cask update_api download_url_tpl pkg_ext
  app_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.app_path")"
  brew_cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.brew_cask")"
  log_debug "app-bundle[$target] action=$action: app_path='$app_path' brew_cask='${brew_cask:-<none>}'"
  [[ -n "$app_path" ]] || return 1

  # brew-cask is the preferred driver; delegate if already brew-managed
  if [[ -n "$brew_cask" ]] && [[ -n "$(_brew_cask_cached_version "$brew_cask")" ]]; then
    log_debug "app-bundle[$target] action: delegating to brew cask ($action '$brew_cask')"
    case "$action" in
      install) brew_cask_install "$brew_cask" ;;
      update)  brew_cask_upgrade "$brew_cask" ;;
    esac
    return
  fi

  update_api="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.update_api")"
  download_url_tpl="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.download_url_tpl")"
  pkg_ext="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.package_ext")"
  [[ -n "$pkg_ext" ]] || pkg_ext="zip"
  log_debug "app-bundle[$target] action: update_api='$update_api' pkg_ext='$pkg_ext'"
  [[ -n "$update_api" && -n "$download_url_tpl" ]] || return 1

  # Fetch latest version from API (JSON array or newline-separated)
  local latest response
  log_debug "app-bundle[$target] action: fetching latest version from '$update_api'"
  response="$(curl -sL --max-time "$(_ucc_curl_timeout metadata)" "$update_api" 2>/dev/null)" || return 1
  latest="$(printf '%s' "$response" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
  log_debug "app-bundle[$target] action: latest version='${latest:-<parse failed>}'"
  [[ -n "$latest" ]] || return 1

  local download_url pkg_file tmp_dir
  download_url="${download_url_tpl//\{version\}/$latest}"
  tmp_dir="$(mktemp -d)"
  pkg_file="$tmp_dir/update.$pkg_ext"
  log_debug "app-bundle[$target] action: downloading '$download_url' → '$pkg_file'"

  ucc_run curl -sL --max-time "$(_ucc_curl_timeout download)" -o "$pkg_file" "$download_url" || { rm -rf "$tmp_dir"; return 1; }

  case "$pkg_ext" in
    dmg)
      local mount_point
      log_debug "app-bundle[$target] action: mounting '$pkg_file'"
      mount_point="$(hdiutil attach "$pkg_file" -nobrowse -readonly 2>/dev/null \
        | awk '/\/Volumes\//{print $NF}' | head -1)"
      log_debug "app-bundle[$target] action: mount_point='${mount_point:-<failed>}'"
      if [[ -z "$mount_point" ]]; then rm -rf "$tmp_dir"; return 1; fi
      local src_app
      src_app="$(find "$mount_point" -maxdepth 1 -name "*.app" -type d | head -1)"
      log_debug "app-bundle[$target] action: src_app='${src_app:-<not found>}'"
      if [[ -n "$src_app" ]]; then
        ucc_run cp -R "$src_app" "${UCC_APPS_DIR:-/Applications}/"
      fi
      hdiutil detach "$mount_point" -quiet 2>/dev/null || true
      [[ -n "$src_app" ]] || { rm -rf "$tmp_dir"; return 1; }
      ;;
    zip)
      log_debug "app-bundle[$target] action: extracting '$pkg_file'"
      ucc_run unzip -q -o "$pkg_file" -d "$tmp_dir/extract" || { rm -rf "$tmp_dir"; return 1; }
      local src_app
      src_app="$(find "$tmp_dir/extract" -maxdepth 2 -name "*.app" -type d | head -1)"
      log_debug "app-bundle[$target] action: src_app='${src_app:-<not found>}'"
      if [[ -n "$src_app" ]]; then
        ucc_run cp -R "$src_app" "${UCC_APPS_DIR:-/Applications}/"
      fi
      [[ -n "$src_app" ]] || { rm -rf "$tmp_dir"; return 1; }
      ;;
    *)
      log_debug "app-bundle[$target] action: unsupported pkg_ext='$pkg_ext'"
      rm -rf "$tmp_dir"; return 1 ;;
  esac

  rm -rf "$tmp_dir"
}

_ucc_driver_app_bundle_evidence() {
  local cfg_dir="$1" yaml="$2" target="$3"
  local app_path brew_cask ver
  app_path="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.app_path")"
  log_debug "app-bundle[$target] evidence: app_path='$app_path'"
  [[ -n "$app_path" && -d "$app_path" ]] || return 1
  brew_cask="$(_ucc_yaml_target_get "$cfg_dir" "$yaml" "$target" "driver.brew_cask")"

  ver="$(_app_bundle_plist_version "$app_path")"
  log_debug "app-bundle[$target] evidence: plist version='${ver:-<unreadable>}'"
  [[ -n "$ver" ]] || return 1
  if [[ -n "$brew_cask" ]] && [[ -n "$(_brew_cask_cached_version "$brew_cask")" ]]; then
    printf 'version=%s  managed=brew-cask  path=%s' "$ver" "$app_path"
  else
    printf 'version=%s  path=%s' "$ver" "$app_path"
  fi
}
