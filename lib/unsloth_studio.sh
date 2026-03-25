#!/usr/bin/env bash
# lib/unsloth_studio.sh — Unsloth Studio setup + launchd targets
# Sourced by components/ai-python-stack.sh

# Usage: register_unsloth_studio_targets <cfg_dir> <yaml_path>
register_unsloth_studio_targets() {
  local cfg_dir="$1" yaml="$2"

  local label plist_marker port host studio_dir log_file plist bin

  label="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_studio.label 2>/dev/null)"
  plist_marker="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_studio.plist_marker 2>/dev/null)"
  port="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_studio.port 2>/dev/null)"
  host="$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_studio.host 2>/dev/null)"
  studio_dir="$HOME/$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_studio.studio_dir 2>/dev/null)"
  log_file="$HOME/$(python3 "$cfg_dir/tools/read_config.py" --get "$yaml" unsloth_studio.log_file 2>/dev/null)"
  plist="$HOME/Library/LaunchAgents/${label}.plist"
  # launchd does not load pyenv shims — resolve absolute binary path at source time
  bin="$(pyenv which unsloth 2>/dev/null || command -v unsloth)"

  # ---- setup target (downloads frontend, creates venv) ----
  eval "_observe_unsloth_setup()  { ucc_asm_package_state \"\$([[ -d '${studio_dir}' ]] && echo 'present' || echo 'absent')\"; }"
  eval "_evidence_unsloth_setup() {
    local ver; ver=\$(pip show unsloth 2>/dev/null | awk '/^Version:/{print \$2}')
    [[ -n \"\$ver\" ]] && printf 'version=%s  ' \"\$ver\"
    printf 'folder=${studio_dir}'
  }"
  eval "_run_unsloth_setup()      { ucc_run unsloth studio setup; }"

  ucc_target_nonruntime \
    --name    "unsloth-studio-setup" \
    --observe _observe_unsloth_setup \
    --evidence _evidence_unsloth_setup \
    --install _run_unsloth_setup \
    --update  _run_unsloth_setup

  # ---- launchd target ----
  eval "_observe_unsloth_launchd() {
    launchctl list 2>/dev/null | grep -q '${label}' || { ucc_asm_service_state 'absent'; return; }
    grep -qF '${plist_marker}' '${plist}' 2>/dev/null || { ucc_asm_service_state 'outdated'; return; }
    ucc_asm_service_state 'loaded'
  }"
  eval "_evidence_unsloth_launchd() {
    local pid ver
    ver=\$(pip show unsloth 2>/dev/null | awk '/^Version:/{print \$2}')
    pid=\$(pgrep -f 'unsloth.*studio' 2>/dev/null | head -1 || true)
    [[ -n \"\$ver\" ]] && printf 'version=%s' \"\$ver\"
    [[ -n \"\$pid\" ]] && printf '  pid=%s  port=${port}  plist=${plist}' \"\$pid\" || printf '  port=${port}  plist=${plist}'
  }"
  eval "_install_unsloth_launchd() {
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
    ucc_run launchctl load '${plist}'
  }"
  eval "_update_unsloth_launchd() {
    launchctl unload '${plist}' 2>/dev/null || true
    _install_unsloth_launchd
  }"

  ucc_target_service \
    --name    "unsloth-studio-launchd" \
    --observe _observe_unsloth_launchd \
    --evidence _evidence_unsloth_launchd \
    --desired "$(ucc_asm_runtime_desired)" \
    --install _install_unsloth_launchd \
    --update  _update_unsloth_launchd
}
