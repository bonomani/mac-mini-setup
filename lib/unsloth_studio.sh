#!/usr/bin/env bash
# lib/unsloth_studio.sh — Unsloth Studio software target
# Sourced by components/ai-python-stack.sh

# Usage: register_unsloth_studio_targets <cfg_dir> <yaml_path>
register_unsloth_studio_targets() {
  local cfg_dir="$1" yaml="$2"

  local label plist_marker port host studio_dir log_file plist bin

  label="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_label 2>/dev/null)"
  plist_marker="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_plist_marker 2>/dev/null)"
  port="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_port 2>/dev/null)"
  host="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_host 2>/dev/null)"
  studio_dir="$HOME/$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_studio_dir 2>/dev/null)"
  log_file="$HOME/$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_log_file 2>/dev/null)"
  plist="$HOME/Library/LaunchAgents/${label}.plist"
  # launchd does not load pyenv shims — resolve absolute binary path at source time
  bin="$(pyenv which unsloth 2>/dev/null || command -v unsloth)"
  eval "_install_unsloth_studio() {
    [[ -d '${studio_dir}' ]] || ucc_run unsloth studio setup || return 1
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
    <string>${bin}</string>
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
    _ucc_wait_for_runtime_probe \"curl -fsS --max-time 5 'http://127.0.0.1:${port}' >/dev/null 2>&1\"
  }"
  eval "_update_unsloth_studio() {
    ucc_run unsloth studio setup || return 1
    launchctl unload '${plist}' 2>/dev/null || true
    _install_unsloth_studio
  }"

  ucc_yaml_runtime_target "$cfg_dir" "$yaml" "unsloth-studio" _install_unsloth_studio _update_unsloth_studio
}
