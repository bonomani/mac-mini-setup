#!/usr/bin/env python3
"""Pin update_class validator + canonical key order rule.

The `update_class: tool|lib` field controls whether a target follows
UIC_PREF_TOOL_UPDATE or UIC_PREF_LIB_UPDATE policy. Until 2026-04-28
this field was read by drivers but not validated, so a typo silently
fell through to the `tool` default.
"""
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
VALIDATOR = REPO / "tools" / "validate_targets_manifest.py"
UCC = REPO / "ucc"


def _run_validator(root: Path):
    r = subprocess.run(
        [sys.executable, str(VALIDATOR), str(root)],
        capture_output=True, text=True,
    )
    return r.returncode, r.stdout + r.stderr


class UpdateClassValidationTests(unittest.TestCase):
    def test_real_manifest_passes(self):
        rc, out = _run_validator(UCC)
        self.assertEqual(rc, 0, out)

    def test_unknown_update_class_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            dst = Path(d) / "ucc"
            shutil.copytree(UCC, dst)
            f = dst / "software" / "ai-python-stack.yaml"
            data = yaml.safe_load(f.read_text())
            # xz already has update_class: lib — flip to a typo.
            data["targets"]["xz"]["update_class"] = "library"
            f.write_text(yaml.dump(data))
            rc, out = _run_validator(dst)
            self.assertNotEqual(rc, 0)
            self.assertIn("update_class", out)
            self.assertIn("library", out)

    def test_known_classes_accepted(self):
        sys.path.insert(0, str(REPO / "tools"))
        try:
            from validate_targets_manifest import KNOWN_UPDATE_CLASSES
        finally:
            sys.path.pop(0)
        self.assertEqual(KNOWN_UPDATE_CLASSES, {"tool", "lib"})


if __name__ == "__main__":
    unittest.main()
