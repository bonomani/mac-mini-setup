#!/usr/bin/env python3
"""Regression tests for driver.kind: capability target shape.

Exercises the validator's positive + negative rules and confirms the
dispatcher's probe-evaluation round-trip on a real migrated target.
Kept standalone — does not depend on the broader scheduler test harness
(which has unrelated pre-existing failures on WSL).
"""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = REPO_ROOT / "tools" / "validate_targets_manifest.py"
UCC = REPO_ROOT / "ucc"


def _run_validator(root: Path):
    r = subprocess.run(
        [sys.executable, str(VALIDATOR), str(root)],
        capture_output=True,
        text=True,
    )
    return r.returncode, r.stdout + r.stderr


def _staged_ucc(fn):
    """Decorator: copy real ucc/ to a temp dir, let fn mutate a YAML, then
    run the validator and return (rc, out)."""
    def wrapped(self):
        with tempfile.TemporaryDirectory() as d:
            dst = Path(d) / "ucc"
            shutil.copytree(UCC, dst)
            target_yaml = dst / "software" / "network-services.yaml"
            data = yaml.safe_load(target_yaml.read_text())
            fn(self, data)
            target_yaml.write_text(yaml.dump(data))
            rc, out = _run_validator(dst)
            self.assertNotEqual(rc, 0, "validator should reject")
            return rc, out
    return wrapped


class CapabilityValidatorTests(unittest.TestCase):
    """Positive + negative schema checks for driver.kind: capability."""

    def test_real_manifest_passes_validator(self):
        """Live ucc/ tree must validate cleanly — this is the acceptance
        signal that the 7 migrated targets are schema-correct."""
        rc, out = _run_validator(UCC)
        self.assertEqual(rc, 0, f"validator failed on real manifest:\n{out}")

    @_staged_ucc
    def test_rejects_legacy_runtime_manager(self, data):
        data["targets"]["mdns-available"]["runtime_manager"] = "capability"

    def test_rejects_legacy_runtime_manager_check(self):
        rc, out = self.test_rejects_legacy_runtime_manager()
        self.assertIn("must not set runtime_manager", out)

    @_staged_ucc
    def test_rejects_legacy_probe_kind(self, data):
        data["targets"]["mdns-available"]["probe_kind"] = "command"

    def test_rejects_legacy_probe_kind_check(self):
        rc, out = self.test_rejects_legacy_probe_kind()
        self.assertIn("must not set probe_kind", out)

    @_staged_ucc
    def test_rejects_legacy_oracle_runtime(self, data):
        data["targets"]["mdns-available"]["oracle"] = {"runtime": "some_fn"}

    def test_rejects_legacy_oracle_runtime_check(self):
        rc, out = self.test_rejects_legacy_oracle_runtime()
        self.assertIn("must not set oracle.runtime", out)

    @_staged_ucc
    def test_rejects_driver_kind_custom(self, data):
        data["targets"]["mdns-available"]["driver"]["kind"] = "custom"
        data["targets"]["mdns-available"]["driver"].pop("probe", None)

    def test_rejects_driver_kind_custom_check(self):
        rc, out = self.test_rejects_driver_kind_custom()
        self.assertIn("requires driver.kind 'capability'", out)

    @_staged_ucc
    def test_rejects_missing_driver_probe(self, data):
        data["targets"]["mdns-available"]["driver"].pop("probe", None)

    def test_rejects_missing_driver_probe_check(self):
        rc, out = self.test_rejects_missing_driver_probe()
        self.assertIn("requires driver.probe", out)


class CapabilityDispatcherRoundTripTests(unittest.TestCase):
    """Confirm ucc_yaml_capability_target + _ucc_observe_yaml_capability_target
    read driver.probe and evaluate it correctly against a real target."""

    def _bash(self, script: str) -> str:
        r = subprocess.run(
            ["bash", "-c", script],
            capture_output=True,
            text=True,
            cwd=REPO_ROOT,
        )
        return r.stdout + r.stderr

    def test_probe_reads_via_yaml_target_get(self):
        """_ucc_yaml_target_get reads driver.probe as the probe function
        name from a real migrated target."""
        out = self._bash(
            'source lib/ucc.sh && '
            '_ucc_yaml_target_get "$(pwd)" '
            '"$(pwd)/ucc/software/network-services.yaml" '
            '"mdns-available" "driver.probe"'
        )
        self.assertEqual(out.strip(), "mdns_is_available")

    def test_kind_reads_as_capability(self):
        out = self._bash(
            'source lib/ucc.sh && '
            '_ucc_yaml_target_get "$(pwd)" '
            '"$(pwd)/ucc/software/network-services.yaml" '
            '"mdns-available" "driver.kind"'
        )
        self.assertEqual(out.strip(), "capability")

    def test_observe_round_trip_running(self):
        """When the probe function succeeds, the capability observer reports
        runtime_state=Running. Stubs network_is_available so the test passes
        offline (the live probe was the previous fragility)."""
        out = self._bash(
            'source lib/ucc.sh && source lib/utils.sh && '
            'network_is_available() { return 0; } && '
            '_ucc_observe_yaml_capability_target "$(pwd)" '
            '"$(pwd)/ucc/software/homebrew.yaml" "network-available"'
        )
        self.assertIn('"runtime_state":"Running"', out)
        self.assertIn('"health_state":"Healthy"', out)

    def test_observe_round_trip_stopped(self):
        """When the probe function fails (sudo_is_available on a box
        with no cached sudo ticket), the capability observer reports
        runtime_state=Stopped."""
        out = self._bash(
            'source lib/ucc.sh && source lib/utils.sh && '
            'sudo -k 2>/dev/null || true; '
            '_ucc_observe_yaml_capability_target "$(pwd)" '
            '"$(pwd)/ucc/system/system.yaml" "sudo-available"'
        )
        self.assertIn('"runtime_state":"Stopped"', out)


class InstallShBatchKeysTests(unittest.TestCase):
    """Static regression tests for the install.sh _UCC_YAML_BATCH_KEYS
    pre-fetch cache list. This is the exact bug commit 2863044 fixed:
    the list was missing `driver.probe` so capability targets returned
    empty runtime_cmd and defaulted to runtime_state=Stopped in the
    full Mac mini run, even though the dispatcher itself had been
    correctly updated.

    These tests are intentionally static (grep install.sh for the key
    list) rather than dynamic. A dynamic test would need to stage a
    fake manifest, populate env vars, and invoke the dispatcher — but
    the simpler static check directly documents the invariant: any
    field the capability dispatcher reads from the cache MUST be in
    _UCC_YAML_BATCH_KEYS."""

    def test_batch_keys_include_driver_probe(self):
        """install.sh's _UCC_YAML_BATCH_KEYS must include driver.probe
        so ucc_yaml_capability_target can read the probe function
        name from the pre-populated cache. Regression for 2863044."""
        install_sh = REPO_ROOT / "install.sh"
        content = install_sh.read_text()
        self.assertIn(
            "driver.probe",
            content,
            "install.sh must reference driver.probe somewhere (in "
            "_UCC_YAML_BATCH_KEYS for the capability target cache). "
            "See commit 2863044 for the regression this test exists "
            "to catch.",
        )

    def test_batch_keys_excludes_oracle_runtime(self):
        """The legacy oracle.runtime key was dropped from _UCC_YAML_BATCH_KEYS
        in commit 2863044 because no target reads it anymore — the
        capability dispatcher now uses driver.probe, and validator
        commit e48da96 hard-rejects oracle.runtime on capability
        profiles. Having the legacy key still in the batch list would
        be dead weight but not harmful; this test exists as an
        explicit reminder of the cleanup."""
        install_sh = REPO_ROOT / "install.sh"
        content = install_sh.read_text()
        self.assertNotIn(
            "oracle.runtime",
            content,
            "install.sh should no longer reference oracle.runtime in "
            "_UCC_YAML_BATCH_KEYS. All capability targets use "
            "driver.probe now (commit e48da96 for the cutover, "
            "commit 2863044 for the batch-keys fix).",
        )


if __name__ == "__main__":
    unittest.main()
