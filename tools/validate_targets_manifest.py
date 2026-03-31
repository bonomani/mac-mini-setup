#!/usr/bin/env python3
import os
import sys
from collections import defaultdict
from pathlib import Path

import yaml


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
KNOWN_PLATFORMS = {"macos", "linux", "wsl", "wsl1", "wsl2"}
KNOWN_PACKAGE_DRIVERS = {
    "brew-bootstrap",
    "custom",
    "brew",
    "macos-clt",
    "vscode-marketplace",
    "npm-global",
    "pip",
    "pyenv-version",
    "ollama-model",
    "app-bundle",
}
KNOWN_RUNTIME_DRIVERS = {
    "brew-service",
    "custom",
    "custom-daemon",
    "desktop-app",
    "docker-compose",
    "launchd",
}
KNOWN_CONFIG_DRIVERS = {
    "brew-analytics",
    "custom",
    "user-defaults",
    "compose-file",
    "docker-settings",
    "git-global-config",
    "host-composition",
    "json-merge",
    "path-export",
    "pip-bootstrap",
    "platform-check",
    "pmset",
    "script-install",
    "shell-bootstrap",
    "shell-file-edit",
    "softwareupdate-defaults",
    "softwareupdate-schedule",
    "symlink-command",
    "user-defaults",
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

REPO_ROOT = Path(__file__).resolve().parent.parent


def stringify(value):
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)


def substitute_scalars(value: str, data: dict) -> str:
    subst = {
        key: stringify(raw)
        for key, raw in data.items()
        if isinstance(raw, (str, int, float, bool))
    }
    import re

    return re.sub(r"\$\{([A-Za-z0-9_.]+)\}", lambda m: subst.get(m.group(1), m.group(0)), value)


def collect_manifest_scalars(value, out: dict[str, str], prefix: str = "") -> None:
    if isinstance(value, dict):
        for key, raw in value.items():
            if not isinstance(key, str) or not key:
                continue
            nested = f"{prefix}.{key}" if prefix else key
            collect_manifest_scalars(raw, out, nested)
        return
    if prefix and isinstance(value, (str, int, float, bool)):
        out[prefix] = stringify(value)


def _driver_block(data):
    driver = data.get("driver")
    return driver if isinstance(driver, dict) else {}


def _action_block(data):
    actions = data.get("actions")
    return actions if isinstance(actions, dict) else {}


def _driver_kind(data):
    driver = _driver_block(data)
    if isinstance(driver.get("kind"), str) and driver.get("kind", "").strip():
        return driver["kind"]
    return ""


def _action_cmd(data, action):
    actions = _action_block(data)
    value = actions.get(action)
    if isinstance(value, str) and value.strip():
        return value
    if action == "update":
        return _action_cmd(data, "install")
    return ""


def _endpoint_url(endpoint, subst_data):
    url = endpoint.get("url", "")
    if isinstance(url, str) and url.strip():
        return substitute_scalars(url, data=subst_data)
    scheme = endpoint.get("scheme", "")
    host = endpoint.get("host", "")
    port = endpoint.get("port", "")
    path = endpoint.get("path", "")
    if not scheme or not host:
        return ""
    scheme = substitute_scalars(stringify(scheme), data=subst_data)
    host = substitute_scalars(stringify(host), data=subst_data)
    port = substitute_scalars(stringify(port), data=subst_data) if port not in ("", None) else ""
    path = substitute_scalars(stringify(path), data=subst_data) if path not in ("", None) else ""
    url = f"{scheme}://{host}"
    if port:
        url += f":{port}"
    if path:
        if not path.startswith("/"):
            path = "/" + path
        url += path
    return url


def parse_gate_names(path: Path):
    gate_names = set()
    if not path.exists():
        return gate_names

    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.startswith("  - name: "):
            gate_names.add(raw[len("  - name: "):].strip())
        elif raw.startswith("gates:") or raw.startswith("    ") or raw.startswith("  "):
            continue
        else:
            raise ValueError(f"{path}:{lineno}: unsupported gate manifest structure")

    return gate_names

def parse_manifest_file(path: Path):
    data = yaml.safe_load(path.read_text()) or {}
    if not isinstance(data, dict):
        raise ValueError(f"{path}: manifest must contain a top-level mapping")

    targets = data.get("targets") or {}
    if not isinstance(targets, dict):
        raise ValueError(f"{path}: top-level 'targets' must be a mapping")

    manifest = dict(data)
    manifest["targets"] = targets

    for name, target_data in targets.items():
        if not isinstance(target_data, dict):
            raise ValueError(f"{path}: target '{name}' must be a mapping")

    return manifest


def _find_yaml_files(path: Path):
    files = list(path.glob("*.yaml"))
    for subdir in ("software", "system"):
        sub = path / subdir
        if sub.is_dir():
            files.extend(sub.glob("*.yaml"))
    return sorted(files, key=lambda f: f.name)


def parse_manifest(path: Path):
    if path.is_dir():
        merged = {"targets": {}, "components": {}}
        files = _find_yaml_files(path)
        if not files:
            raise ValueError(f"{path}: no *.yaml files found")
        for file in files:
            manifest = parse_manifest_file(file)
            component = manifest.get("component")
            if component:
                if component in merged["components"]:
                    raise ValueError(f"{file}: duplicate component '{component}'")
                merged["components"][component] = {
                    "primary_profile": manifest.get("primary_profile", ""),
                    "libs": manifest.get("libs", ""),
                    "runner": manifest.get("runner", ""),
                    "on_fail": manifest.get("on_fail", ""),
                    "file": str(file),
                }
            for name, data in manifest["targets"].items():
                if name in merged["targets"]:
                    raise ValueError(f"{file}: duplicate target '{name}'")
                target_data = dict(data)
                scalars = {}
                for key, value in manifest.items():
                    if key == "targets":
                        continue
                    collect_manifest_scalars(value, scalars, key)
                target_data["__manifest_scalars__"] = scalars
                merged["targets"][name] = target_data
        return merged
    manifest = parse_manifest_file(path)
    for name, data in manifest["targets"].items():
        target_data = dict(data)
        scalars = {}
        for key, value in manifest.items():
            if key == "targets":
                continue
            collect_manifest_scalars(value, scalars, key)
        target_data["__manifest_scalars__"] = scalars
        manifest["targets"][name] = target_data
    return {"targets": manifest["targets"], "components": {}}


def _declared_platforms(manifest_data):
    platforms = manifest_data.get("platforms") or []
    if isinstance(platforms, list):
        return [p for p in platforms if isinstance(p, str)]
    return []


def _validate_generated_target_collection(
    manifest_data: dict,
    section_name: str,
    errors: list[str],
    *,
    required_dep: str | None = None,
):
    target_names = manifest_data.get(section_name)
    if target_names is None:
        return
    if not isinstance(target_names, list):
        errors.append(f"component '{manifest_data.get('component', '?')}' section '{section_name}' must be a list")
        return

    targets = manifest_data.get("targets") or {}
    for item in target_names:
        if not isinstance(item, str) or not item.strip():
            errors.append(
                f"component '{manifest_data.get('component', '?')}' section '{section_name}' entries must be non-empty target names"
            )
            continue
        target = targets.get(item)
        if not isinstance(target, dict):
            errors.append(
                f"component '{manifest_data.get('component', '?')}' section '{section_name}' references unknown target '{item}'"
            )
            continue
        if target.get("profile") != "configured":
            errors.append(f"generated target '{item}' in section '{section_name}' must use profile 'configured'")
        if target.get("type") != "package":
            errors.append(f"generated target '{item}' in section '{section_name}' must use type 'package'")
        if target.get("state_model") != "package":
            errors.append(f"generated target '{item}' in section '{section_name}' must use state_model 'package'")
        if not isinstance(target.get("provided_by_tool"), str) or not target.get("provided_by_tool", "").strip():
            errors.append(f"generated target '{item}' in section '{section_name}' requires provided_by_tool")
        driver_kind = (target.get("driver") or {}).get("kind", "")
        driver_dispatched = bool(driver_kind) and driver_kind != "custom"
        if not driver_dispatched:
            if not isinstance(target.get("observe_cmd"), str) or not target.get("observe_cmd", "").strip():
                errors.append(f"generated target '{item}' in section '{section_name}' requires observe_cmd")
            if not _action_cmd(target, "install"):
                errors.append(f"generated target '{item}' in section '{section_name}' requires actions.install")
        if required_dep and required_dep not in (target.get("depends_on") or []):
            errors.append(
                f"generated target '{item}' in section '{section_name}' must depend on '{required_dep}'"
            )


def _target_dep_union(data):
    deps = list(data.get("depends_on", []) or [])
    platform_deps = data.get("depends_on_by_platform") or {}
    if isinstance(platform_deps, dict):
        for items in platform_deps.values():
            if isinstance(items, list):
                deps.extend(items)
    return deps


def _target_soft_dep_targets(data):
    deps = []
    for dep in data.get("soft_depends_on", []) or []:
        if isinstance(dep, str) and dep and not dep.startswith("gate:"):
            deps.append(dep)
    return deps


def _target_order_union(data):
    return _target_dep_union(data) + _target_soft_dep_targets(data)


def _effective_target_deps(data):
    deps = list(data.get("depends_on", []) or [])
    platform = (os.environ.get("HOST_PLATFORM_VARIANT") or "").strip()
    family = (os.environ.get("HOST_PLATFORM") or "").strip()
    candidates = []
    if platform:
        candidates.append(platform)
    if family and family not in candidates:
        candidates.append(family)
    if family == "wsl" and "linux" not in candidates:
        candidates.append("linux")

    platform_deps = data.get("depends_on_by_platform") or {}
    if isinstance(platform_deps, dict):
        for candidate in candidates:
            items = platform_deps.get(candidate) or []
            if isinstance(items, list):
                deps.extend(items)
    return deps


def validate(manifest, known_gates):
    targets = manifest["targets"]
    components = manifest["components"]
    errors = []

    for component, meta in components.items():
        file_path = meta.get("file")
        manifest_data = parse_manifest_file(Path(file_path)) if file_path else {}
        platforms = _declared_platforms(manifest_data)
        for platform in platforms:
            if platform not in KNOWN_PLATFORMS:
                errors.append(f"component '{component}' declares unknown platform '{platform}'")

        platform_tool_preferences = manifest_data.get("platform_tool_preferences") or {}
        if platform_tool_preferences:
            if not isinstance(platform_tool_preferences, dict):
                errors.append(f"component '{component}' platform_tool_preferences must be a mapping")
            else:
                for platform, tools in platform_tool_preferences.items():
                    if platform not in KNOWN_PLATFORMS:
                        errors.append(f"component '{component}' tool preference declares unknown platform '{platform}'")
                    if platforms and platform not in platforms:
                        errors.append(f"component '{component}' tool preference platform '{platform}' not declared in platforms")
                    if not isinstance(tools, list) or not tools or not all(isinstance(tool, str) and tool for tool in tools):
                        errors.append(f"component '{component}' tool preference for '{platform}' must be a non-empty list of strings")

        _validate_generated_target_collection(manifest_data, "vscode_extensions", errors, required_dep="vscode-code-cmd")
        _validate_generated_target_collection(manifest_data, "pip_groups", errors, required_dep="pip-latest")
        _validate_generated_target_collection(manifest_data, "cli_tools", errors, required_dep="homebrew")
        _validate_generated_target_collection(manifest_data, "npm_packages", errors, required_dep="node-lts")
        _validate_generated_target_collection(manifest_data, "casks", errors, required_dep="homebrew")
        for section_name in ("small", "medium", "large"):
            _validate_generated_target_collection(manifest_data, section_name, errors, required_dep="ollama")

    for name, data in targets.items():
        profile = data.get("profile")
        target_type = data.get("type")
        component = data.get("component")
        if not profile:
            errors.append(f"target '{name}' missing profile")
        elif profile not in KNOWN_PROFILES:
            errors.append(f"target '{name}' has unknown profile '{profile}'")
        if not target_type:
            errors.append(f"target '{name}' missing type")
        elif target_type not in KNOWN_TARGET_TYPES:
            errors.append(f"target '{name}' has unknown type '{target_type}'")
        if not component:
            errors.append(f"target '{name}' missing component")

        for field in (
            "display_name",
            "provided_by_tool",
            "runtime_manager",
            "probe_kind",
            "observe_success",
            "observe_failure",
            "observe_cmd",
            "desired_value",
            "desired_cmd",
            "dependency_gate",
            "stopped_installation",
            "stopped_runtime",
            "stopped_health",
            "stopped_dependencies",
        ):
            value = data.get(field)
            if value is not None and (not isinstance(value, str) or not value.strip()):
                errors.append(f"target '{name}' field '{field}' must be a non-empty string")

        admin_required = data.get("admin_required")
        if admin_required is not None and not isinstance(admin_required, bool):
            errors.append(f"target '{name}' field 'admin_required' must be a boolean")

        driver = data.get("driver")
        if driver is not None:
            if not isinstance(driver, dict) or not driver:
                errors.append(f"target '{name}' driver must be a non-empty mapping")
            else:
                for key, value in driver.items():
                    if not isinstance(key, str) or not key.strip():
                        errors.append(f"target '{name}' driver contains an empty key")
                    elif not isinstance(value, (str, int, float, bool)):
                        errors.append(f"target '{name}' driver '{key}' must be a scalar")

        actions = data.get("actions")
        if actions is not None:
            if not isinstance(actions, dict) or not actions:
                errors.append(f"target '{name}' actions must be a non-empty mapping")
            else:
                for key, value in actions.items():
                    if key not in {"install", "update"}:
                        errors.append(f"target '{name}' actions contains unsupported key '{key}'")
                    if not isinstance(value, str) or not value.strip():
                        errors.append(f"target '{name}' actions '{key}' must be a non-empty string")

        state_model = data.get("state_model")
        oracle = data.get("oracle")
        if state_model is not None and state_model not in KNOWN_STATE_MODELS:
            errors.append(f"target '{name}' has unknown state_model '{state_model}'")
        if target_type == "package" and state_model != "package":
            errors.append(f"target '{name}' type 'package' requires state_model 'package'")
        if target_type == "package":
            package_driver = _driver_kind(data)
            if not isinstance(package_driver, str) or not package_driver.strip():
                errors.append(f"target '{name}' type 'package' requires driver.kind")
            elif package_driver not in KNOWN_PACKAGE_DRIVERS:
                errors.append(f"target '{name}' has unknown package driver '{package_driver}'")
            if not isinstance(data.get("provided_by_tool"), str) or not data.get("provided_by_tool", "").strip():
                errors.append(f"target '{name}' type 'package' requires provided_by_tool")
            driver_dispatched = bool(package_driver) and package_driver != "custom"
            if not driver_dispatched:
                has_observe_cmd = isinstance(data.get("observe_cmd"), str) and data.get("observe_cmd", "").strip()
                if not has_observe_cmd:
                    errors.append(f"target '{name}' type 'package' requires observe_cmd")
                if not isinstance(data.get("evidence"), dict) or not data.get("evidence"):
                    errors.append(f"target '{name}' type 'package' requires evidence")
                if not _action_cmd(data, "install"):
                    errors.append(f"target '{name}' type 'package' requires actions.install")
                if not _action_cmd(data, "update"):
                    errors.append(f"target '{name}' type 'package' requires actions.update")
        if target_type == "config" and profile != "parametric" and state_model != "config":
            errors.append(f"target '{name}' type 'config' with profile '{profile}' requires state_model 'config'")
        if target_type == "config":
            config_driver = _driver_kind(data)
            if not isinstance(data.get("display_name"), str) or not data.get("display_name", "").strip():
                errors.append(f"target '{name}' type 'config' requires display_name")
            if not isinstance(config_driver, str) or not config_driver.strip():
                errors.append(f"target '{name}' type 'config' requires driver.kind")
            elif config_driver not in KNOWN_CONFIG_DRIVERS:
                errors.append(f"target '{name}' has unknown config driver '{config_driver}'")
            config_driver_dispatched = bool(config_driver) and config_driver != "custom"
            if not config_driver_dispatched:
                if not isinstance(data.get("evidence"), dict) or not data.get("evidence"):
                    errors.append(f"target '{name}' type 'config' requires evidence")
        if target_type == "precondition" and state_model != "config":
            errors.append(f"target '{name}' type 'precondition' requires state_model 'config'")
        if target_type == "precondition":
            config_driver = _driver_kind(data)
            if not isinstance(data.get("display_name"), str) or not data.get("display_name", "").strip():
                errors.append(f"target '{name}' type 'precondition' requires display_name")
            if not isinstance(config_driver, str) or not config_driver.strip():
                errors.append(f"target '{name}' type 'precondition' requires driver.kind")
            elif config_driver not in KNOWN_CONFIG_DRIVERS:
                errors.append(f"target '{name}' has unknown config driver '{config_driver}'")
            if not isinstance((oracle or {}).get("configured"), str) or not (oracle or {}).get("configured", "").strip():
                errors.append(f"target '{name}' type 'precondition' requires oracle.configured")
            if not isinstance(data.get("evidence"), dict) or not data.get("evidence"):
                errors.append(f"target '{name}' type 'precondition' requires evidence")
        dependency_gate = data.get("dependency_gate")
        if isinstance(dependency_gate, str) and dependency_gate and dependency_gate not in known_gates:
            errors.append(f"target '{name}' dependency_gate unknown gate '{dependency_gate}'")

        ordered_keys = [key for key in data.keys() if key in CANONICAL_TARGET_KEY_RANK]
        previous_rank = -1
        for key in ordered_keys:
            rank = CANONICAL_TARGET_KEY_RANK[key]
            if rank < previous_rank:
                errors.append(
                    f"target '{name}' keys must follow canonical order: "
                    + ", ".join(CANONICAL_TARGET_KEY_ORDER)
                )
                break
            previous_rank = rank

        if oracle is not None:
            if not isinstance(oracle, dict):
                errors.append(f"target '{name}' oracle must be a mapping")
            else:
                for level, cmd in oracle.items():
                    if not isinstance(level, str) or not level.strip():
                        errors.append(f"target '{name}' oracle contains an empty key")
                    if not isinstance(cmd, str) or not cmd.strip():
                        errors.append(f"target '{name}' oracle '{level}' must be a non-empty string")

        evidence = data.get("evidence")
        if evidence is not None:
            if not isinstance(evidence, dict):
                errors.append(f"target '{name}' evidence must be a mapping")
            else:
                for key, cmd in evidence.items():
                    if not isinstance(key, str) or not key.strip():
                        errors.append(f"target '{name}' evidence contains an empty key")
                    if not isinstance(cmd, str) or not cmd.strip():
                        errors.append(f"target '{name}' evidence '{key}' must be a non-empty string")

        endpoints = data.get("endpoints")
        if endpoints is not None:
            if not isinstance(endpoints, list):
                errors.append(f"target '{name}' endpoints must be a list")
            else:
                for index, endpoint in enumerate(endpoints):
                    if not isinstance(endpoint, dict):
                        errors.append(f"target '{name}' endpoint {index} must be a mapping")
                        continue
                    if not isinstance(endpoint.get("name"), str) or not endpoint.get("name", "").strip():
                        errors.append(f"target '{name}' endpoint {index} missing name")
                    url = endpoint.get("url")
                    scheme = endpoint.get("scheme")
                    host = endpoint.get("host")
                    if url is None:
                        if not (isinstance(scheme, (str, int, float, bool)) and stringify(scheme).strip()):
                            errors.append(f"target '{name}' endpoint {index} requires url or scheme")
                        if not (isinstance(host, (str, int, float, bool)) and stringify(host).strip()):
                            errors.append(f"target '{name}' endpoint {index} requires url or host")
                    elif not isinstance(url, str) or not url.strip():
                        errors.append(f"target '{name}' endpoint {index} url must be a non-empty string")
                    for field in ("scheme", "host", "path"):
                        value = endpoint.get(field)
                        if value is not None and (not isinstance(value, str) or not value.strip()):
                            errors.append(f"target '{name}' endpoint {index} field '{field}' must be a non-empty string")
                    port = endpoint.get("port")
                    if port is not None and not isinstance(port, (str, int)):
                        errors.append(f"target '{name}' endpoint {index} field 'port' must be a string or int")
                    note = endpoint.get("note")
                    if note is not None and not isinstance(note, str):
                        errors.append(f"target '{name}' endpoint {index} note must be a string")
            if profile != "runtime":
                errors.append(f"target '{name}' endpoints require profile 'runtime'")

        if profile == "runtime":
            if target_type != "runtime":
                errors.append(f"target '{name}' profile '{profile}' requires type 'runtime'")
            if not isinstance(data.get("display_name"), str) or not data.get("display_name", "").strip():
                errors.append(f"target '{name}' profile '{profile}' requires display_name")
            runtime_driver = _driver_kind(data)
            if not isinstance(runtime_driver, str) or not runtime_driver.strip():
                errors.append(f"target '{name}' profile '{profile}' requires driver.kind")
            elif runtime_driver not in KNOWN_RUNTIME_DRIVERS:
                errors.append(f"target '{name}' has unknown runtime driver '{runtime_driver}'")
            if not isinstance(data.get("runtime_manager"), str) or not data.get("runtime_manager", "").strip():
                errors.append(f"target '{name}' profile '{profile}' requires runtime_manager")
            if not isinstance(data.get("probe_kind"), str) or not data.get("probe_kind", "").strip():
                errors.append(f"target '{name}' profile '{profile}' requires probe_kind")
            if not isinstance((oracle or {}).get("runtime"), str) or not (oracle or {}).get("runtime", "").strip():
                errors.append(f"target '{name}' profile '{profile}' requires oracle.runtime")
            if not isinstance(data.get("evidence"), dict) or not data.get("evidence"):
                errors.append(f"target '{name}' profile '{profile}' requires evidence")

        if profile == "capability":
            if target_type != "capability":
                errors.append(f"target '{name}' profile '{profile}' requires type 'capability'")
            if not isinstance(data.get("runtime_manager"), str) or not data.get("runtime_manager", "").strip():
                errors.append(f"target '{name}' profile '{profile}' requires runtime_manager")
            if not isinstance(data.get("probe_kind"), str) or not data.get("probe_kind", "").strip():
                errors.append(f"target '{name}' profile '{profile}' requires probe_kind")
            if not isinstance((oracle or {}).get("runtime"), str) or not (oracle or {}).get("runtime", "").strip():
                errors.append(f"target '{name}' profile '{profile}' requires oracle.runtime")

        if state_model == "parametric":
            if profile != "parametric":
                errors.append(f"target '{name}' state_model 'parametric' requires profile 'parametric'")
            if target_type != "config":
                errors.append(f"target '{name}' state_model 'parametric' requires type 'config'")
            has_install_update = bool(_action_cmd(data, "install") or _action_cmd(data, "update"))
            has_observe_cmd = isinstance(data.get("observe_cmd"), str) and data.get("observe_cmd", "").strip()
            has_desired_value = isinstance(data.get("desired_value"), str) and data.get("desired_value", "").strip()
            has_desired_cmd = isinstance(data.get("desired_cmd"), str) and data.get("desired_cmd", "").strip()
            if has_install_update and not has_observe_cmd:
                errors.append(f"target '{name}' state_model 'parametric' with install/update commands requires observe_cmd")
            if has_install_update and not has_desired_value and not has_desired_cmd:
                errors.append(f"target '{name}' state_model 'parametric' with install/update commands requires desired_value or desired_cmd")

        if _action_cmd(data, "install") or _action_cmd(data, "update"):
            has_observe_cmd = isinstance(data.get("observe_cmd"), str) and data.get("observe_cmd", "").strip()
            if profile == "runtime":
                pass
            elif state_model is None:
                errors.append(f"target '{name}' with install/update commands requires state_model")
            elif state_model == "parametric":
                pass
            elif not has_observe_cmd and (
                not isinstance((oracle or {}).get("configured"), str) or not (oracle or {}).get("configured", "").strip()
            ):
                errors.append(f"target '{name}' with install/update commands requires observe_cmd or oracle.configured")

        driver_kind_val = _driver_kind(data)
        driver_dispatched_any = bool(driver_kind_val) and driver_kind_val != "custom"
        if admin_required is True:
            if not driver_dispatched_any and not _action_cmd(data, "install") and not _action_cmd(data, "update"):
                errors.append(f"target '{name}' field 'admin_required' requires actions.install or actions.update")

        for action_name in ("install", "update"):
            action_cmd = _action_cmd(data, action_name)
            if action_cmd and "sudo " in action_cmd and admin_required is not True:
                errors.append(f"target '{name}' action '{action_name}' uses sudo and requires admin_required: true")

        depends_on = data.get("depends_on", []) or []
        if not isinstance(depends_on, list):
            errors.append(f"target '{name}' depends_on must be a list")
            depends_on = []
        for dep in depends_on:
            if not isinstance(dep, str) or not dep.strip():
                errors.append(f"target '{name}' depends_on entries must be non-empty strings")
                continue
            if dep not in targets:
                errors.append(f"target '{name}' depends_on unknown target '{dep}'")

        platform_deps = data.get("depends_on_by_platform") or {}
        if platform_deps:
            if not isinstance(platform_deps, dict):
                errors.append(f"target '{name}' depends_on_by_platform must be a mapping")
            else:
                for platform, deps in platform_deps.items():
                    if platform not in KNOWN_PLATFORMS:
                        errors.append(f"target '{name}' depends_on_by_platform unknown platform '{platform}'")
                    if not isinstance(deps, list):
                        errors.append(f"target '{name}' depends_on_by_platform '{platform}' must be a list")
                        continue
                    for dep in deps:
                        if not isinstance(dep, str) or not dep.strip():
                            errors.append(f"target '{name}' depends_on_by_platform '{platform}' entries must be non-empty strings")
                            continue
                        if dep not in targets:
                            errors.append(f"target '{name}' depends_on_by_platform '{platform}' unknown target '{dep}'")

        soft_depends_on = data.get("soft_depends_on", []) or []
        if not isinstance(soft_depends_on, list):
            errors.append(f"target '{name}' soft_depends_on must be a list")
            soft_depends_on = []
        for dep in soft_depends_on:
            if not isinstance(dep, str) or not dep.strip():
                errors.append(f"target '{name}' soft_depends_on entries must be non-empty strings")
                continue
            if dep.startswith("gate:"):
                gate = dep.split(":", 1)[1]
                if gate not in known_gates:
                    errors.append(f"target '{name}' soft_depends_on unknown gate '{gate}'")
            elif dep not in targets:
                errors.append(f"target '{name}' soft_depends_on unknown target '{dep}'")

    for component, meta in components.items():
        primary_profile = meta.get("primary_profile")
        if not primary_profile:
            errors.append(f"component '{component}' missing primary_profile")
        elif primary_profile not in KNOWN_PROFILES:
            errors.append(f"component '{component}' has unknown primary_profile '{primary_profile}'")

        component_targets = [name for name, data in targets.items() if data.get("component") == component]
        if not component_targets:
            errors.append(f"component '{component}' has no targets")

    for name, data in targets.items():
        component = data.get("component")
        if component and component in components:
            continue
        if component and components:
            errors.append(f"target '{name}' references undeclared component '{component}'")

    graph = defaultdict(list)
    indegree = {name: 0 for name in targets}
    for name, data in targets.items():
        for dep in _target_order_union(data):
            graph[dep].append(name)
            indegree[name] += 1

    queue = [name for name, degree in indegree.items() if degree == 0]
    ordered = []
    while queue:
        node = queue.pop(0)
        ordered.append(node)
        for child in graph[node]:
            indegree[child] -= 1
            if indegree[child] == 0:
                queue.append(child)

    if len(ordered) != len(targets):
        remaining = sorted(name for name, degree in indegree.items() if degree > 0)
        errors.append(f"dependency cycle detected among: {', '.join(remaining)}")

    return errors, ordered


def component_order(manifest, topo_ordered=None):
    """Return components in an order consistent with target dependencies.

    Builds a component-level dependency graph by inspecting which component
    owns each target's depends_on entries, then runs Kahn's topo sort on
    components.  Ties are broken alphabetically for determinism.
    """
    targets = manifest["targets"]
    components = list(manifest["components"].keys())

    # Build component → set-of-component-deps from target depends_on edges
    comp_deps = {c: set() for c in components}
    comp_graph = defaultdict(list)
    comp_indegree = {c: 0 for c in components}

    for tname, tdata in targets.items():
        comp = tdata.get("component")
        if not comp or comp not in comp_deps:
            continue
        for dep_target in _target_order_union(tdata):
            dep_comp = targets.get(dep_target, {}).get("component")
            if dep_comp and dep_comp != comp and dep_comp not in comp_deps[comp]:
                comp_deps[comp].add(dep_comp)
                comp_graph[dep_comp].append(comp)
                comp_indegree[comp] += 1

    queue = sorted(c for c, deg in comp_indegree.items() if deg == 0)
    ordered = []
    while queue:
        node = queue.pop(0)
        ordered.append(node)
        children = sorted(comp_graph[node])
        for child in children:
            comp_indegree[child] -= 1
            if comp_indegree[child] == 0:
                queue.append(child)
                queue.sort()
    for c in components:
        if c not in ordered:
            ordered.append(c)
    return ordered


def main():
    args = sys.argv[1:]
    deps_mode = False
    display_name_mode = False
    soft_deps_mode = False
    components_mode = False
    dispatch_mode = False
    all_dispatch_mode = False
    all_deps_mode = False
    all_soft_deps_mode = False
    all_ordered_targets_mode = False
    all_display_names_mode = False
    all_caches_mode = False
    oracles_mode = False
    runtime_endpoints_mode = False
    ordered_targets_mode = False
    target_name = None
    if len(args) >= 2 and args[0] == "--deps":
        deps_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 2 and args[0] == "--display-name":
        display_name_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 2 and args[0] == "--soft-deps":
        soft_deps_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 2 and args[0] == "--dispatch":
        dispatch_mode = True
        target_name = args[1]
        args = args[2:]
    elif len(args) >= 1 and args[0] == "--all-dispatch":
        all_dispatch_mode = True
        args = args[1:]
    elif len(args) >= 1 and args[0] == "--all-deps":
        all_deps_mode = True
        args = args[1:]
    elif len(args) >= 1 and args[0] == "--all-soft-deps":
        all_soft_deps_mode = True
        args = args[1:]
    elif len(args) >= 1 and args[0] == "--all-ordered-targets":
        all_ordered_targets_mode = True
        args = args[1:]
    elif len(args) >= 1 and args[0] == "--all-display-names":
        all_display_names_mode = True
        args = args[1:]
    elif len(args) >= 1 and args[0] == "--all-caches":
        all_caches_mode = True
        args = args[1:]
    elif len(args) >= 2 and args[0] == "--ordered-targets":
        target_name = args[1]
        args = args[2:]
        ordered_targets_mode = True
    elif len(args) >= 1 and args[0] == "--components":
        components_mode = True
        args = args[1:]
    elif len(args) >= 1 and args[0] == "--oracles":
        oracles_mode = True
        args = args[1:]
    elif len(args) >= 1 and args[0] == "--runtime-endpoints":
        runtime_endpoints_mode = True
        args = args[1:]

    path = Path(args[0]) if args else Path("ucc")
    try:
        manifest = parse_manifest(path)
        known_gates = parse_gate_names(REPO_ROOT / "policy" / "gates.yaml")
        errors, ordered = validate(manifest, known_gates)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1

    if deps_mode:
        for dep in _effective_target_deps(manifest["targets"].get(target_name, {}) or {}):
            print(dep)
        return 0

    if display_name_mode:
        data = manifest["targets"].get(target_name, {}) or {}
        display_name = data.get("display_name", "")
        subst_data = data.get("__manifest_scalars__") or {}
        if isinstance(display_name, str):
            display_name = substitute_scalars(display_name, data=subst_data)
        print(display_name)
        return 0

    if all_caches_mode:
        # --all-deps
        print("__section__\tall_deps")
        for target_name, data in manifest["targets"].items():
            deps = _effective_target_deps(data or {})
            if deps:
                print("{}\t{}".format(target_name, ",".join(deps)))
        # --all-soft-deps
        print("__section__\tall_soft_deps")
        for target_name, data in manifest["targets"].items():
            soft_deps = (data or {}).get("soft_depends_on", []) or []
            if soft_deps:
                print("{}\t{}".format(target_name, ",".join(soft_deps)))
        # --all-ordered-targets
        print("__section__\tall_ordered_targets")
        from collections import defaultdict
        comp_targets = defaultdict(list)
        for name in ordered:
            data = manifest["targets"].get(name, {})
            comp = data.get("component", "")
            if comp:
                comp_targets[comp].append(name)
        for comp, targets in comp_targets.items():
            print("{}\t{}".format(comp, ",".join(targets)))
        # --all-display-names
        print("__section__\tall_display_names")
        for name, data in manifest["targets"].items():
            data = data or {}
            display_name = data.get("display_name", "") or name
            subst_data = data.get("__manifest_scalars__") or {}
            if isinstance(display_name, str):
                display_name = substitute_scalars(display_name, data=subst_data)
            print("{}\t{}".format(name, display_name or name))
        return 0

    if all_display_names_mode:
        for name, data in manifest["targets"].items():
            data = data or {}
            display_name = data.get("display_name", "") or name
            subst_data = data.get("__manifest_scalars__") or {}
            if isinstance(display_name, str):
                display_name = substitute_scalars(display_name, data=subst_data)
            print("{}\t{}".format(name, display_name or name))
        return 0

    if soft_deps_mode:
        for dep in manifest["targets"].get(target_name, {}).get("soft_depends_on", []):
            print(dep)
        return 0

    if dispatch_mode:
        meta = manifest["components"].get(target_name, {})
        print(meta.get("libs", ""))
        print(meta.get("runner", ""))
        print(meta.get("on_fail", ""))
        print(meta.get("file", ""))
        return 0

    if all_deps_mode:
        for target_name, data in manifest["targets"].items():
            deps = _effective_target_deps(data or {})
            if deps:
                print("{}\t{}".format(target_name, ",".join(deps)))
        return 0

    if all_soft_deps_mode:
        for target_name, data in manifest["targets"].items():
            soft_deps = (data or {}).get("soft_depends_on", []) or []
            if soft_deps:
                print("{}\t{}".format(target_name, ",".join(soft_deps)))
        return 0

    if all_dispatch_mode:
        for comp_name in component_order(manifest, ordered):
            meta = manifest["components"].get(comp_name, {})
            print("{}\t{}\t{}\t{}\t{}".format(
                comp_name,
                meta.get("libs", ""),
                meta.get("runner", ""),
                meta.get("on_fail", ""),
                meta.get("file", ""),
            ))
        return 0

    if all_ordered_targets_mode:
        from collections import defaultdict
        comp_targets = defaultdict(list)
        for name in ordered:
            data = manifest["targets"].get(name, {})
            comp = data.get("component", "")
            if comp:
                comp_targets[comp].append(name)
        for comp, targets in comp_targets.items():
            print("{}\t{}".format(comp, ",".join(targets)))
        return 0

    if ordered_targets_mode:
        for name in ordered:
            data = manifest["targets"].get(name, {})
            if data.get("component") == target_name:
                print(name)
        return 0

    if components_mode:
        for component in component_order(manifest, ordered):
            print(component)
        return 0

    if oracles_mode:
        # Output tab-separated: target_name \t profile \t oracle_level \t oracle_cmd
        for name in ordered:
            data = manifest["targets"][name]
            profile = data.get("profile", "")
            oracle = data.get("oracle", {})
            if not oracle:
                continue
            for level, cmd in oracle.items():
                print(f"{name}\t{profile}\t{level}\t{cmd}")
        return 0

    if runtime_endpoints_mode:
        # Output tab-separated: target_name \t endpoint_name \t url \t note
        for name in ordered:
            data = manifest["targets"][name]
            if data.get("profile") != "runtime":
                continue
            endpoints = data.get("endpoints") or []
            if not isinstance(endpoints, list):
                continue
            for endpoint in endpoints:
                if not isinstance(endpoint, dict):
                    continue
                subst_data = data.get("__manifest_scalars__") or {}
                url = _endpoint_url(endpoint, subst_data)
                if not url:
                    continue
                note = endpoint.get("note", "")
                if isinstance(note, str):
                    note = substitute_scalars(note, data=subst_data)
                print(
                    f"{name}\t{endpoint.get('name', '')}\t{url}\t{note}"
                )
        return 0

    print(f"OK: {len(manifest['targets'])} orchestration targets validated")
    print("Topological order:")
    for name in ordered:
        print(f"  - {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
