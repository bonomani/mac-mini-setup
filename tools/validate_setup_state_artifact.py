#!/usr/bin/env python3
"""Self-contained validator for setup-state artifacts.

Validates a YAML artifact (default: docs/setup-state-artifact.yaml) against
the state-axis vocabulary defined in docs/setup-state-model.md. Does not
depend on the sibling `asm` repo — the previous external dispatch was
removed because the file it called did not exist in this tree.
"""
from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml  # type: ignore
    _HAS_YAML = True
except ImportError:
    _HAS_YAML = False


AXES = {
    "installation_state": {
        "Absent", "Installing", "Installed", "Configuring", "Configured",
        "Upgrading", "InstallFailed", "ConfigFailed", "UpgradeFailed",
    },
    "runtime_state": {
        "NeverStarted", "Starting", "Running", "Stopped", "Crashed",
    },
    "health_state": {
        "Unknown", "Healthy", "Degraded", "Unhealthy", "Unavailable",
    },
    "admin_state": {"Enabled", "Maintenance", "Disabled"},
    "dependency_state": {
        "DepsUnknown", "DepsReady", "DepsDegraded", "DepsFailed",
    },
}
DERIVED = {
    "Present", "Ready", "Operational", "Broken",
    "ManagedStop", "Transient", "NonOperational",
}
PROFILE_LAYERS = {
    "minimal_operational", "operational", "extended_operational", "full",
}
TRANSITION_AXES = {"installation", "runtime", "health", "admin", "dependency"}


def _load(path: Path) -> dict:
    text = path.read_text()
    if _HAS_YAML:
        return yaml.safe_load(text) or {}
    # Minimal fallback parser used only when PyYAML is unavailable.
    data: dict = {}
    list_key = None
    map_key = None
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if line.startswith("  - ") and list_key:
            data.setdefault(list_key, []).append(line[4:].strip().strip('"'))
            continue
        if line.startswith("  ") and map_key and ":" in line:
            k, v = line.strip().split(":", 1)
            data.setdefault(map_key, {})[k.strip()] = v.strip().strip('"')
            continue
        list_key = map_key = None
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        k, v = k.strip(), v.strip()
        if v == "":
            data[k] = []
            list_key = k
            map_key = k
        else:
            data[k] = v.strip('"')
    return data


def validate(state: dict) -> list[str]:
    errors: list[str] = []
    pl = state.get("profile_layer")
    if pl and pl not in PROFILE_LAYERS:
        errors.append(f"profile_layer={pl!r} not in {sorted(PROFILE_LAYERS)}")
    for axis, allowed in AXES.items():
        if axis not in state:
            errors.append(f"missing required axis: {axis}")
            continue
        v = state[axis]
        if v not in allowed:
            errors.append(f"{axis}={v!r} not in {sorted(allowed)}")
    derived = state.get("derived_states") or []
    if not isinstance(derived, list):
        errors.append("derived_states must be a list")
    else:
        for d in derived:
            if d not in DERIVED:
                errors.append(f"derived_states: {d!r} not in {sorted(DERIVED)}")
    lt = state.get("last_transition")
    if lt is not None:
        if not isinstance(lt, dict):
            errors.append("last_transition must be a mapping")
        else:
            ax = lt.get("axis")
            if ax not in TRANSITION_AXES:
                errors.append(
                    f"last_transition.axis={ax!r} not in {sorted(TRANSITION_AXES)}"
                )
            for f in ("from", "to"):
                if f not in lt:
                    errors.append(f"last_transition missing {f!r}")
    return errors


def main(argv: list[str]) -> int:
    repo_root = Path(__file__).resolve().parents[1]
    if len(argv) > 2:
        print(
            "usage: validate_setup_state_artifact.py [artifact.yaml]",
            file=sys.stderr,
        )
        return 2
    artifact = (
        Path(argv[1]).resolve()
        if len(argv) == 2
        else repo_root / "docs" / "setup-state-artifact.yaml"
    )
    if not artifact.exists():
        print(f"artifact not found: {artifact}", file=sys.stderr)
        return 2
    try:
        state = _load(artifact)
    except Exception as e:
        print(f"failed to parse {artifact}: {e}", file=sys.stderr)
        return 2
    errors = validate(state)
    if errors:
        print(f"INVALID {artifact}", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    print(f"VALID {artifact}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
