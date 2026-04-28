#!/usr/bin/env python3
"""Tests for tools/validate_setup_state_artifact.py.

The validator was previously broken: it required an explicit path AND
delegated to an external `../asm/tools/validate_software_state.py` that
does not exist in this tree. These tests pin the new self-contained
contract: it validates the repo's own sample artifact by default and
catches schema violations on its own.
"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOL = REPO_ROOT / "tools" / "validate_setup_state_artifact.py"
SAMPLE = REPO_ROOT / "docs" / "setup-state-artifact.yaml"


def _run(args):
    return subprocess.run(
        [sys.executable, str(TOOL), *args],
        capture_output=True, text=True, cwd=REPO_ROOT,
    )


class ValidatorTests(unittest.TestCase):
    def test_default_artifact_is_valid(self):
        """No-arg invocation validates the repo's sample artifact."""
        r = _run([])
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("VALID", r.stdout)

    def test_sample_artifact_explicit_is_valid(self):
        r = _run([str(SAMPLE)])
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_unknown_axis_value_rejected(self):
        with tempfile.NamedTemporaryFile(
            "w", suffix=".yaml", delete=False
        ) as f:
            f.write(SAMPLE.read_text().replace("Running", "Bogus"))
            tmp = f.name
        try:
            r = _run([tmp])
            self.assertEqual(r.returncode, 1)
            self.assertIn("runtime_state", r.stderr)
            self.assertIn("Bogus", r.stderr)
        finally:
            os.unlink(tmp)

    def test_missing_axis_rejected(self):
        body = (
            "profile_layer: operational\n"
            "installation_state: Configured\n"
            "runtime_state: Running\n"
            "health_state: Healthy\n"
            "admin_state: Enabled\n"
            # dependency_state intentionally missing
        )
        with tempfile.NamedTemporaryFile(
            "w", suffix=".yaml", delete=False
        ) as f:
            f.write(body)
            tmp = f.name
        try:
            r = _run([tmp])
            self.assertEqual(r.returncode, 1)
            self.assertIn("dependency_state", r.stderr)
        finally:
            os.unlink(tmp)

    def test_nonexistent_file_returns_2(self):
        r = _run(["/no/such/file.yaml"])
        self.assertEqual(r.returncode, 2)


if __name__ == "__main__":
    unittest.main()
