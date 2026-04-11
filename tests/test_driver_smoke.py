#!/usr/bin/env python3
"""Per-driver smoke tests — source each driver file and invoke its
`_ucc_driver_<kind>_observe` hook against a minimal synthetic YAML
fixture. Catches the class of regression where a driver sources
clean (bash -n passes) but one of its hook functions has an unbound
variable, a typo in a case branch, or a missing helper call that
only fires at runtime.

Does NOT cover:
  - Capability targets (dispatched via ucc_yaml_capability_target,
    not through _ucc_driver_capability_observe; see
    tests/test_capability_driver.py).
  - Install actions (fixture targets are never executed).
  - Meta-drivers that delegate to other drivers (npm-global, package —
    their logic is tested via the pkg driver they delegate through).
  - vscode-marketplace (retired; use kind: pkg with vscode backend).

For each driver kind we provide the minimum required fields from
DRIVER_SCHEMA, filled with values designed to be absent on the test
host (nonexistent formulas, packages, directories, etc). That means
each observe hook returns the target's 'missing' state cleanly —
exactly what we want: exit 0 or 1 (both are 'driver dispatched'
outcomes), not a bash parse error or an unbound-variable crash.
"""

import os
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent

# Minimum fake driver-field payloads per kind. The values are meant to
# point at things that don't exist on the test host so observe returns
# the 'missing' state cleanly. We do NOT need them to represent real
# config — only to satisfy the driver's required-field reads.
#
# Keys here must stay in sync with DRIVER_SCHEMA[kind]['required'] in
# tools/validate_targets_manifest.py. If a driver adds a new required
# field, the smoke test will trip with a KeyError on target dispatch
# until this dict is updated.
FAKE_DRIVER_FIELDS = {
    "app-bundle":              {"app_path": "/Applications/XyzSmoke.app",
                                "brew_cask": "xyz-smoke-nonexistent"},
    "brew":                    {"ref": "xyz-smoke-nonexistent-formula"},
    "brew-analytics":          {},
    "brew-unlink":             {"formula": "xyz-smoke-nonexistent"},
    "build-deps":              {},
    "compose-apply":           {"path_env": "XYZ_SMOKE_NONEXISTENT"},
    "compose-file":            {"path_env": "XYZ_SMOKE_NONEXISTENT"},
    "custom-daemon":           {"bin": "/opt/xyz-smoke/bin/xyz",
                                "process": "xyz-smoke-nonexistent-proc"},
    "docker-compose-service":  {"service_name": "xyz-smoke-svc"},
    "git-global":              {},
    "git-repo":                {"repo": "https://example.invalid/xyz.git",
                                "dest": "/tmp/xyz-smoke-nonexistent-repo"},
    "home-artifact":           {"subkind": "script",
                                "script_name": "xyz-smoke-nonexistent"},
    "json-merge":              {"settings_relpath": "Smoke/xyz.json",
                                "patch_relpath": "smoke/xyz-patch.json"},
    "nvm":                     {"nvm_dir": ".nvm-xyz-smoke"},
    "nvm-version":             {"version": "99", "nvm_dir": ".nvm-xyz-smoke"},
    "path-export":             {"bin_dir": "bin-xyz-smoke",
                                "shell_profile": ".xyz-smoke-profile"},
    "pip":                     {"probe_pkg": "xyz_smoke_nonexistent_pkg",
                                "install_packages": "xyz_smoke_nonexistent_pkg"},
    "pip-bootstrap":           {},
    "pkg":                     {"backends": [{"native-pm": "xyz-smoke"}]},
    "pyenv-brew":              {},
    "script-installer":        {"install_url": "https://example.invalid/xyz.sh",
                                "install_dir": "xyz-smoke-nonexistent"},
    "service":                 {"backend": "brew",
                                "ref": "xyz-smoke-nonexistent-svc"},
    "setting":                 {"backend": "defaults",
                                "domain": "com.xyz.smoke",
                                "key": "xyz", "value": "smoke",
                                "type": "string"},
    "softwareupdate-schedule": {},
    "zsh-config":              {"key": "XYZ_SMOKE", "value": "smoke",
                                "config_file": ".zshrc-xyz-smoke"},
}


def _write_fake_manifest(tmp_path: Path, kind: str, target_name: str) -> Path:
    """Write a minimal ucc/software/smoke.yaml that declares one target
    using the given kind and the matching FAKE_DRIVER_FIELDS. Returns
    the path to the YAML file."""
    ucc = tmp_path / "ucc" / "software"
    ucc.mkdir(parents=True, exist_ok=True)
    fields = FAKE_DRIVER_FIELDS[kind]
    manifest = {
        "component": "smoke",
        "primary_profile": "runtime",
        "libs": [],
        "platforms": ["linux", "macos", "wsl2"],
        "targets": {
            target_name: {
                "component": "smoke",
                "profile": "runtime",
                "type": "package",
                "state_model": "package",
                "display_name": f"Smoke {kind}",
                "driver": {"kind": kind, **fields},
            },
        },
    }
    yaml_path = ucc / "smoke.yaml"
    yaml_path.write_text(yaml.dump(manifest))
    return yaml_path


def _observe_fn_name(kind: str) -> str:
    return f"_ucc_driver_{kind.replace('-', '_')}_observe"


@pytest.mark.parametrize("kind", sorted(FAKE_DRIVER_FIELDS.keys()))
def test_driver_observe_smoke(kind, tmp_path):
    """Invoke _ucc_driver_<kind>_observe against a minimal synthetic
    target and assert it dispatches cleanly. The target is designed
    to resolve to the driver's 'missing' state, so observe returns 0
    or 1 (both valid). A bash parse error, unbound variable, or
    missing function crashes with a higher exit code and fails here."""
    target = f"fake-{kind.replace('-', '_')}"
    yaml_path = _write_fake_manifest(tmp_path, kind, target)
    fn = _observe_fn_name(kind)

    script = textwrap.dedent(f"""\
        set -u
        cd {REPO_ROOT}
        source lib/ucc.sh
        source lib/utils.sh
        declare -f {fn} >/dev/null || {{ echo "MISSING: {fn}" >&2; exit 2; }}
        {fn} "{REPO_ROOT}" "{yaml_path}" "{target}" >/tmp/smoke_stdout 2>/tmp/smoke_stderr
        rc=$?
        # Driver dispatched cleanly if rc ≤ 1; higher means a real crash.
        [[ $rc -le 1 ]] && exit 0 || exit $rc
    """)

    result = subprocess.run(
        ["bash", "-c", script],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=15,
    )

    # On failure, surface the raw bash stderr for debugging.
    assert result.returncode == 0, (
        f"driver kind '{kind}' observe hook crashed:\n"
        f"  rc={result.returncode}\n"
        f"  stdout={result.stdout!r}\n"
        f"  stderr={result.stderr!r}"
    )


def test_fake_driver_fields_match_schema_required():
    """Sanity check: FAKE_DRIVER_FIELDS must provide every field in
    DRIVER_SCHEMA[kind]['required'] for each kind we smoke-test. If
    a driver grows a new required field, this test will trip before
    the per-driver smoke test does, with a clearer error message."""
    sys.path.insert(0, str(REPO_ROOT / "tools"))
    from validate_targets_manifest import DRIVER_SCHEMA

    for kind, fake_fields in FAKE_DRIVER_FIELDS.items():
        assert kind in DRIVER_SCHEMA, \
            f"FAKE_DRIVER_FIELDS has '{kind}' but DRIVER_SCHEMA does not"
        required = set(DRIVER_SCHEMA[kind]["required"])
        provided = set(fake_fields.keys())
        missing = required - provided
        assert not missing, \
            f"kind '{kind}' missing required fields in FAKE_DRIVER_FIELDS: {missing}"


def test_smoke_coverage_vs_drivers_registered():
    """Sanity check: every driver that defines a _ucc_driver_<kind>_observe
    hook in lib/drivers/ is either in FAKE_DRIVER_FIELDS or explicitly
    excluded with a documented reason below. Prevents a new driver from
    silently dropping out of smoke-test coverage."""
    import re

    # Drivers we explicitly skip and why. If you add a new skip, add a
    # one-line reason so future readers know we considered it.
    SKIP_KINDS = {
        # Capability dispatch goes through ucc_yaml_capability_target, not
        # through _ucc_driver_capability_observe. Coverage lives in
        # tests/test_capability_driver.py.
        "capability",
    }

    registered = set()
    for driver_file in sorted((REPO_ROOT / "lib" / "drivers").glob("*.sh")):
        content = driver_file.read_text()
        for m in re.finditer(r"^_ucc_driver_([a-z_]+)_observe\s*\(\)", content, re.MULTILINE):
            kind = m.group(1).replace("_", "-")
            registered.add(kind)

    covered = set(FAKE_DRIVER_FIELDS.keys())
    uncovered = registered - covered - SKIP_KINDS
    assert not uncovered, (
        f"new drivers with _observe hooks not in FAKE_DRIVER_FIELDS: {sorted(uncovered)}. "
        f"Add them to FAKE_DRIVER_FIELDS or to SKIP_KINDS with a reason."
    )
