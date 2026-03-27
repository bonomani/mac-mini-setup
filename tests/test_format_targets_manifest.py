from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FORMATTER = ROOT / "tools" / "format_targets_manifest.py"


class FormatTargetsManifestTests(unittest.TestCase):
    def test_formatter_reorders_target_keys_and_check_passes_after_format(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = Path(tmp) / "fake.yaml"
            manifest.write_text(
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    targets:
                      pkg:
                        observe_cmd: "printf present"
                        state_model: package
                        component: fake
                        update_cmd: "true"
                        display_name: Demo
                        type: package
                        package_driver: brew-formula
                        provided_by_tool: brew
                        install_cmd: "true"
                        profile: configured
                        evidence:
                          version: "printf 1.0.0"
                    """
                ),
                encoding="utf-8",
            )

            check_before = subprocess.run(
                ["python3", str(FORMATTER), "--check", str(manifest)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(check_before.returncode, 0)

            result = subprocess.run(
                ["python3", str(FORMATTER), str(manifest)],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)

            rendered = manifest.read_text(encoding="utf-8")
            self.assertLess(rendered.index("component: fake"), rendered.index("profile: configured"))
            self.assertLess(rendered.index("profile: configured"), rendered.index("type: package"))
            self.assertLess(rendered.index("type: package"), rendered.index("state_model: package"))
            self.assertLess(rendered.index("state_model: package"), rendered.index("display_name: Demo"))
            self.assertLess(rendered.index("display_name: Demo"), rendered.index("provided_by_tool: brew"))
            self.assertLess(rendered.index("provided_by_tool: brew"), rendered.index("package_driver: brew-formula"))
            self.assertLess(rendered.index("package_driver: brew-formula"), rendered.index("observe_cmd: printf present"))
            self.assertLess(rendered.index("observe_cmd: printf present"), rendered.index("evidence:"))
            self.assertLess(rendered.index("evidence:"), rendered.index("install_cmd: 'true'"))
            self.assertLess(rendered.index("install_cmd: 'true'"), rendered.index("update_cmd: 'true'"))

            check_after = subprocess.run(
                ["python3", str(FORMATTER), "--check", str(manifest)],
                text=True,
                capture_output=True,
            )
            self.assertEqual(check_after.returncode, 0, msg=check_after.stderr)


if __name__ == "__main__":
    unittest.main()
