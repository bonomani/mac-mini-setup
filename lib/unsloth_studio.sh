#!/usr/bin/env bash
# lib/unsloth_studio.sh — Unsloth Studio runtime targets (macOS launchd + Linux systemd)
# Sourced by components/ai-python-stack.sh

# Return 0 if PyTorch Metal MPS is available on this host.
torch_mps_available() {
  python3 -c "import torch; raise SystemExit(0 if torch.backends.mps.is_available() else 1)" 2>/dev/null
}

# Print 'available' or 'unavailable (CPU only)' depending on MPS support.
torch_mps_status() {
  python3 -c "import torch; print('available' if torch.backends.mps.is_available() else 'unavailable (CPU only)')" \
    2>/dev/null || printf 'unavailable (CPU only)'
}

# Resolve absolute path to the unsloth binary — fails fast if not found.
# launchd/systemd do not load pyenv shims so we must bake in the absolute path.
_unsloth_bin() {
  local bin
  bin="$(pyenv which unsloth 2>/dev/null || command -v unsloth 2>/dev/null)"
  if [[ -z "$bin" ]]; then
    log_error "unsloth binary not found — is the unsloth package installed?"
    return 1
  fi
  printf '%s' "$bin"
}

# Usage: register_unsloth_studio_targets <cfg_dir> <yaml_path>
# macOS: manages unsloth-studio as a launchd user agent.
register_unsloth_studio_targets() {
  local cfg_dir="$1" yaml="$2"

  local label plist_marker plist_relpath port host studio_dir log_file plist bin
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      unsloth_label) label="$value" ;;
      unsloth_plist_marker) plist_marker="$value" ;;
      unsloth_plist_relpath) plist_relpath="$value" ;;
      unsloth_port) port="$value" ;;
      unsloth_host) host="$value" ;;
      unsloth_studio_dir) studio_dir="$HOME/$value" ;;
      unsloth_log_file) log_file="$HOME/$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" \
    unsloth_label \
    unsloth_plist_marker \
    unsloth_plist_relpath \
    unsloth_port \
    unsloth_host \
    unsloth_studio_dir \
    unsloth_log_file)
  plist="$HOME/${plist_relpath}"

  eval "_install_unsloth_studio() {
    local _bin
    _bin=\"\$(_unsloth_bin)\" || return 1
    mkdir -p '\$(dirname '${plist}')'
    cat > '${plist}' <<PLIST
${plist_marker}
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>
  <key>Label</key>             <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>\${_bin}</string>
    <string>studio</string>
    <string>-H</string><string>${host}</string>
    <string>-p</string><string>${port}</string>
  </array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
  <key>StandardOutPath</key>   <string>${log_file}</string>
  <key>StandardErrorPath</key> <string>${log_file}</string>
  <key>WorkingDirectory</key>  <string>\$HOME</string>
</dict>
</plist>
PLIST
    launchctl unload '${plist}' 2>/dev/null || true
    ucc_run launchctl load '${plist}'
    UCC_RUNTIME_WAIT_ATTEMPTS=10 \\
    UCC_RUNTIME_WAIT_INTERVAL=2 \\
    _ucc_wait_for_runtime_probe \"curl -fsS --max-time 5 'http://127.0.0.1:${port}' >/dev/null 2>&1\"
  }"
  eval "_update_unsloth_studio() {
    launchctl unload '${plist}' 2>/dev/null || true
    _install_unsloth_studio
  }"

  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "unsloth-studio" _install_unsloth_studio _update_unsloth_studio
}

# Usage: register_unsloth_studio_service_targets <cfg_dir> <yaml_path>
# Linux/WSL2: manages unsloth-studio as a systemd user service.
register_unsloth_studio_service_targets() {
  local cfg_dir="$1" yaml="$2"

  local port host log_file service_name
  while IFS=$'\t' read -r -d '' key value; do
    case "$key" in
      unsloth_service_name) service_name="$value" ;;
      unsloth_port) port="$value" ;;
      unsloth_host) host="$value" ;;
      unsloth_log_file) log_file="$HOME/$value" ;;
    esac
  done < <(yaml_get_many "$cfg_dir" "$yaml" \
    unsloth_service_name \
    unsloth_port \
    unsloth_host \
    unsloth_log_file)
  local service_file="$HOME/.config/systemd/user/${service_name}.service"

  eval "_install_unsloth_studio_service() {
    local _bin
    _bin=\"\$(_unsloth_bin)\" || return 1
    mkdir -p '\$(dirname '${service_file}')'
    cat > '${service_file}' <<UNIT
[Unit]
Description=Unsloth Studio
After=network.target

[Service]
ExecStart=\${_bin} studio -H ${host} -p ${port}
Restart=always
StandardOutput=append:${log_file}
StandardError=append:${log_file}

[Install]
WantedBy=default.target
UNIT
    ucc_run systemctl --user daemon-reload
    ucc_run systemctl --user enable --now '${service_name}'
    UCC_RUNTIME_WAIT_ATTEMPTS=10 \\
    UCC_RUNTIME_WAIT_INTERVAL=2 \\
    _ucc_wait_for_runtime_probe \"curl -fsS --max-time 5 'http://127.0.0.1:${port}' >/dev/null 2>&1\"
  }"
  eval "_update_unsloth_studio_service() {
    _install_unsloth_studio_service
  }"

  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "unsloth-studio-service" _install_unsloth_studio_service _update_unsloth_studio_service
}
