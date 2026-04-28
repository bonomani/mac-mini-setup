#!/usr/bin/env python3
"""Pin contracts of lib/ucc_parametric.sh helpers.

Two helpers extracted 2026-04-28 to remove duplicated JSON-patch
plumbing in docker-resources / docker-privileged-ports apply paths:
  _ucc_parametric_apply_json_patch <settings> <basename> <patch_json>
  _ucc_parametric_json_field <path> <key> [default]
"""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def _bash(script: str, cfg_dir: str) -> tuple[int, str]:
    full = f"export CFG_DIR={cfg_dir}\nsource lib/ucc.sh\n{script}\n"
    r = subprocess.run(
        ["bash", "-c", full],
        capture_output=True, text=True, cwd=REPO,
    )
    return r.returncode, r.stdout + r.stderr


class ApplyJsonPatchTests(unittest.TestCase):
    def test_writes_only_patched_keys_others_preserved(self):
        with tempfile.TemporaryDirectory() as d:
            settings = Path(d) / "settings.json"
            settings.write_text(json.dumps({"keep": 1, "memoryMiB": 8192}))
            rc, out = _bash(
                f'_ucc_parametric_apply_json_patch "{settings}" '
                f'"patch.json" \'{{"memoryMiB": 49152, "cpus": 10}}\'',
                cfg_dir=str(REPO),
            )
            self.assertEqual(rc, 0, out)
            after = json.loads(settings.read_text())
            self.assertEqual(after["keep"], 1)
            self.assertEqual(after["memoryMiB"], 49152)
            self.assertEqual(after["cpus"], 10)

    def test_no_op_when_patch_already_satisfied(self):
        with tempfile.TemporaryDirectory() as d:
            settings = Path(d) / "settings.json"
            before = {"k": "v", "n": 3}
            settings.write_text(json.dumps(before))
            rc, _ = _bash(
                f'_ucc_parametric_apply_json_patch "{settings}" '
                f'"patch.json" \'{{"k": "v"}}\'',
                cfg_dir=str(REPO),
            )
            self.assertEqual(rc, 0)
            self.assertEqual(json.loads(settings.read_text()), before)

    def test_drift_detection_via_field_read(self):
        with tempfile.TemporaryDirectory() as d:
            settings = Path(d) / "settings.json"
            settings.write_text(json.dumps({"memoryMiB": 8192}))
            rc, out = _bash(
                f'val="$(_ucc_parametric_json_field "{settings}" memoryMiB)"; '
                f'test "$val" = "8192" && echo OK',
                cfg_dir=str(REPO),
            )
            self.assertEqual(rc, 0, out)
            self.assertIn("OK", out)

    def test_missing_file_returns_default(self):
        with tempfile.TemporaryDirectory() as d:
            rc, out = _bash(
                f'val="$(_ucc_parametric_json_field "{d}/nope.json" any 42)"; '
                f'test "$val" = "42" && echo OK',
                cfg_dir=str(REPO),
            )
            self.assertEqual(rc, 0, out)
            self.assertIn("OK", out)

    def test_missing_key_returns_default(self):
        with tempfile.TemporaryDirectory() as d:
            settings = Path(d) / "settings.json"
            settings.write_text(json.dumps({"other": 1}))
            rc, out = _bash(
                f'val="$(_ucc_parametric_json_field "{settings}" missing fb)"; '
                f'test "$val" = "fb" && echo OK',
                cfg_dir=str(REPO),
            )
            self.assertEqual(rc, 0, out)
            self.assertIn("OK", out)

    def test_helper_validates_required_args(self):
        with tempfile.TemporaryDirectory() as d:
            rc, _ = _bash(
                '_ucc_parametric_apply_json_patch "" "" ""',
                cfg_dir=str(REPO),
            )
            self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
