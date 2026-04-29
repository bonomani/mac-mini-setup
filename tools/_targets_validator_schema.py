"""Schema constants for `validate_targets_manifest.py`.

Extracted 2026-04-29 (PLAN refactor #3, slice 2). The main validator
re-imports these names so existing test imports
(`from validate_targets_manifest import DRIVER_SCHEMA, CANONICAL_TARGET_KEY_ORDER,
KNOWN_UPDATE_CLASSES`) keep working unchanged.
"""
from __future__ import annotations

import os

KNOWN_PROFILES = {"presence", "configured", "runtime", "capability", "parametric", "verification"}
KNOWN_TARGET_TYPES = {
    "package",
    "config",
    "runtime",
    "capability",
    "precondition",
    "service",
}
KNOWN_STATE_MODELS = {"package", "config", "parametric"}
KNOWN_UPDATE_CLASSES = {"tool", "lib"}
KNOWN_PLATFORMS = {"macos", "linux", "wsl", "wsl1", "wsl2"}

# Maps driver.kind → (implicit depends_on target, provided_by_tool)
# Drivers not listed here have no implicit dependency.
# "package" is platform-aware — resolved at runtime by _resolve_driver_meta().
_DRIVER_META_STATIC = {
    "brew":                  ("homebrew",       "brew"),
    "app-bundle":            ("homebrew",       "brew-cask"),
    "pip":                   ("pip-latest",     "pip"),
    "pip-bootstrap":         ("python",         "pip"),
    "npm-global":            ("node-lts",       "npm"),
    "vscode-marketplace":    ("vscode-code-cmd","vscode-marketplace"),
    "pyenv-brew":            (None,             None),  # platform-aware: brew on macOS, git clone elsewhere
    "nvm":                   ("homebrew",       "nvm-installer"),
    "nvm-version":           ("nvm",            "nvm"),
    "service":               (None,             None),  # backend-aware, see lib/drivers/service.sh
    "pkg":                   (None,             None),  # backend-aware, see lib/drivers/pkg.sh
    "docker-compose-service":("docker-desktop", "docker-compose"),
    "git-repo":              (None,             "git"),
}

# Platform-aware driver meta for "package" driver
_PACKAGE_DRIVER_META = {
    "macos": ("homebrew", "brew"),
    "linux": ("build-deps", "native-package-manager"),
    "wsl":   ("build-deps", "native-package-manager"),
    "wsl2":  ("build-deps", "native-package-manager"),
}

# Platform-aware driver meta for "pyenv-brew" driver
_PYENV_DRIVER_META = {
    "macos": ("homebrew", "brew"),
    "linux": (None,       "git"),
    "wsl":   (None,       "git"),
    "wsl2":  (None,       "git"),
}

def _resolve_driver_meta():
    """Build the effective DRIVER_META dict, resolving platform-aware entries."""
    meta = dict(_DRIVER_META_STATIC)
    platform = (os.environ.get("HOST_PLATFORM") or "").strip()
    variant = (os.environ.get("HOST_PLATFORM_VARIANT") or "").strip()
    # Try variant first (wsl2), then family (wsl/linux), then default (macos)
    for candidate in [variant, platform, "macos"]:
        if candidate in _PACKAGE_DRIVER_META:
            meta["package"] = _PACKAGE_DRIVER_META[candidate]
            break
    for candidate in [variant, platform, "macos"]:
        if candidate in _PYENV_DRIVER_META:
            meta["pyenv-brew"] = _PYENV_DRIVER_META[candidate]
            break
    return meta

DRIVER_META = _resolve_driver_meta()
# Maps driver.kind → { required: [keys], optional: [keys] }
# Drivers not listed here accept any keys (custom, etc.)
DRIVER_SCHEMA = {
    "brew":                   {"required": ["ref"], "optional": ["cask", "greedy_auto_updates", "previous_ref"]},
    "service":                {"required": ["backend"], "optional": ["ref", "plist", "launchd_dir"]},
    "brew-analytics":         {"required": [], "optional": []},
    "brew-unlink":            {"required": ["formula"], "optional": []},
    "app-bundle":             {"required": ["app_path", "brew_cask"], "optional": ["update_api", "download_url_tpl", "package_ext"]},
    "pip":                    {"required": ["probe_pkg", "install_packages"], "optional": ["min_version", "isolation"]},
    "pip-bootstrap":          {"required": [], "optional": []},
    "npm-global":             {"required": ["package"], "optional": ["bin", "migration_safety"]},
    "vscode-marketplace":     {"required": ["extension_id"], "optional": []},
    "pyenv-brew":             {"required": [], "optional": []},
    "nvm":                    {"required": ["nvm_dir"], "optional": []},
    "nvm-version":            {"required": ["version", "nvm_dir"], "optional": []},
    "docker-compose-service": {"required": ["service_name"], "optional": []},
    "compose-file":           {"required": ["path_env"], "optional": []},
    "custom-daemon":          {"required": ["bin", "process"], "optional": ["github_repo", "log_path", "start_cmd", "self_updating", "version_probe_path", "install_app_path", "pending_update_glob"]},
    "json-merge":             {"required": ["settings_relpath", "patch_relpath"], "optional": []},
    "setting":                {"required": ["backend", "key", "value"], "optional": ["domain", "type", "requires_sudo"]},
    "pkg":                    {"required": ["backends"], "optional": ["bin", "github_repo", "migration_safety", "curl_args", "greedy_auto_updates"]},
    "softwareupdate-schedule":{"required": [], "optional": []},
    "home-artifact":          {"required": ["subkind"], "optional": ["script_name", "bin_dir", "src_path", "link_relpath", "cmd", "hint"]},
    "script-installer":       {"required": ["install_url", "install_dir"], "optional": ["install_args", "upgrade_script"]},
    "zsh-config":             {"required": ["key", "value", "config_file"], "optional": []},
    "path-export":            {"required": ["bin_dir", "shell_profile"], "optional": []},
    "git-global":             {"required": [], "optional": []},
    "build-deps":             {"required": [], "optional": []},
    "git-repo":               {"required": ["repo", "dest"], "optional": ["branch", "upstream"]},
    "package":                {"required": ["ref"], "optional": ["cask", "greedy_auto_updates", "previous_ref", "apt_ref", "dnf_ref", "pacman_ref", "fallback_install_url", "fallback_install_args", "update_cmd", "bin", "self_updating"]},
    "capability":             {"required": ["probe"], "optional": []},
    "compose-apply":          {"required": ["path_env"], "optional": ["pull_policy_env"]},
}

KNOWN_PACKAGE_DRIVERS = {
    "build-deps",
    "brew-bootstrap",
    "git-repo",
    "package",
    "pkg",
    "custom",
    "brew",
    "macos-clt",
    "pip",
    "pyenv-brew",
    "nvm",
    "nvm-version",
    "app-bundle",
}
KNOWN_RUNTIME_DRIVERS = {
    "compose-apply",
    "compose-file",
    "custom",
    "custom-daemon",
    "docker-compose-service",
    "service",
}
KNOWN_CONFIG_DRIVERS = {
    "home-artifact",
    "brew-analytics",
    "brew-unlink",
    "compose-file",
    "custom",
    "git-global",
    "git-global-config",
    "json-merge",
    "path-export",
    "pip-bootstrap",
    "platform-check",
    "script-install",
    "script-installer",
    "setting",
    "shell-bootstrap",
    "shell-file-edit",
    "softwareupdate-schedule",
    "symlink-command",
    "zsh-config",
}
KNOWN_CAPABILITY_DRIVERS = {
    "capability",
}
CANONICAL_TARGET_KEY_ORDER = [
    "component",
    "profile",
    "type",
    "state_model",
    "display_name",
    "depends_on",
    "depends_on_by_platform",
    "soft_depends_on",
    "provided_by_tool",
    "admin_required",
    "update_class",
    "driver",
    "runtime_manager",
    "probe_kind",
    "oracle",
    "observe_cmd",
    "desired_value",
    "desired_cmd",
    "evidence",
    "endpoints",
    "stopped_installation",
    "stopped_runtime",
    "stopped_health",
    "stopped_dependencies",
    "actions",
]
CANONICAL_TARGET_KEY_RANK = {key: idx for idx, key in enumerate(CANONICAL_TARGET_KEY_ORDER)}
