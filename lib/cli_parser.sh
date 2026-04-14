#!/usr/bin/env bash
# lib/cli_parser.sh — Command-line argument parsing for install.sh
# Sourced by install.sh after libs are loaded.
#
# Usage:
#   cli_parse_args "$@"
#     → populates TO_RUN[] with positional args (component/target names)
#     → sets UCC_DRY_RUN, UCC_MODE, UCC_INTERACTIVE, UCC_DEFAULT_SELECTION,
#       UCC_DEBUG, UIC_PREFLIGHT, UCC_TARGET_SET, UIC_PREF_* env vars
#
# Caller provides COMPONENTS[] array (populated by _load_components) for
# the usage() help output.

cli_usage() {
  cat <<EOF

Usage: $0 [options] [component|target ...]

Without arguments, uses default-selection preference (all or none).
Pass a component name to run that component.
Pass a target name (not a component) to run only that target.

Options:
  --mode install    Install missing components (default)
  --mode update     Update already-installed components
  --all             Select all components and targets
  --none            Select nothing (show current state only)
  --mode check      Observe current state without changing anything (drift detection)
  --dry-run         Show what would change without applying it
  --interactive     Prompt for preferences and confirm each change
  --no-interactive  Skip all prompts (CI/automation mode)
  --preflight       Evaluate UIC gates and preferences; do NOT converge
  --pref key=value  Set a UIC preference for this run only (repeatable)
  --show-overrides  Print user overrides (UCC_OVERRIDE__* env + target-overrides.yaml) and exit
  --debug           Show DEBUG-level output
  -h, --help        Show this help

Available components:
$(printf '  %s\n' "${COMPONENTS[@]}")

Examples:
  $0                                    # full install
  $0 --dry-run                          # preview full install
  $0 --mode update                      # update everything
  $0 --mode update --dry-run            # preview updates
  $0 ollama ai-python-stack             # run specific components
  $0 --mode update ollama               # update Ollama only
  $0 unsloth-studio                     # run single target (auto-resolves component)
  $0 --pref preferred-driver-policy=migrate docker  # migrate Docker from DMG to brew-cask

EOF
  exit 0
}

# Parse all CLI args into exported env vars + TO_RUN[] array.
# Caller must have TO_RUN declared as an array before calling.
cli_parse_args() {
  export UCC_TARGET_SET=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)       export UCC_DRY_RUN=1;     shift ;;
      --mode)          export UCC_MODE="$2";    shift 2 ;;
      --interactive)   export UCC_INTERACTIVE=1; shift ;;
      --no-interactive) export UCC_INTERACTIVE=0; shift ;;
      --all)           export UCC_DEFAULT_SELECTION=all;  shift ;;
      --none)          export UCC_DEFAULT_SELECTION=none; shift ;;
      --debug)         export UCC_DEBUG=1;      shift ;;
      --preflight)     export UIC_PREFLIGHT=1;  shift ;;
      --show-overrides)
        # Print effective user overrides (env + overlay) and exit.
        # Sources lib so the helpers are available without running the full pipeline.
        # shellcheck disable=SC1091
        source "$(dirname "$0")/lib/ucc_targets.sh" 2>/dev/null || true
        printf '%-8s  %-40s  %-30s  %s\n' SOURCE TARGET KEY VALUE
        _ucc_user_override_list 2>/dev/null \
          | awk -F'\t' '{printf "%-8s  %-40s  %-30s  %s\n", $1, $2, $3, $4}'
        exit 0
        ;;
      --pref)
        local _pref_kv="$2"; shift 2
        local _pref_key="${_pref_kv%%=*}"
        local _pref_val="${_pref_kv#*=}"
        local _pref_env="UIC_PREF_$(echo "${_pref_key//-/_}" | tr '[:lower:]' '[:upper:]')"
        export "${_pref_env}=${_pref_val}"
        ;;
      -h|--help)       cli_usage ;;
      -*)              log_warn "Unknown option: $1"; shift ;;
      *)               TO_RUN+=("$1"); shift ;;
    esac
  done
}

# Resolve UCC_INTERACTIVE mode. Consults (in order):
#   1. Already-set UCC_INTERACTIVE env var (from --interactive/--no-interactive)
#   2. interactive=yes|no line in $UIC_PREF_FILE (~/.ai-stack/preferences.env)
#   3. Interactive TTY prompt (if /dev/tty available)
#   4. Default: 0 (non-interactive)
cli_resolve_interactive_mode() {
  [[ -n "${UCC_INTERACTIVE:-}" ]] && return 0
  local _saved_interactive=""
  local _pf="${UIC_PREF_FILE:-$HOME/.ai-stack/preferences.env}"
  if [[ -f "$_pf" ]]; then
    _saved_interactive="$(grep -E '^interactive=' "$_pf" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  fi
  if [[ "$_saved_interactive" == "no" ]]; then
    export UCC_INTERACTIVE=0
  elif [[ "$_saved_interactive" == "yes" ]]; then
    export UCC_INTERACTIVE=1
  elif [[ -c /dev/tty ]]; then
    printf '\n  [?] Run in interactive mode? (*1=yes, 2=no) → '
    local _im_choice
    read -r _im_choice < /dev/tty
    [[ "$_im_choice" == "2" ]] && export UCC_INTERACTIVE=0 || export UCC_INTERACTIVE=1
  else
    export UCC_INTERACTIVE=0
  fi
}
