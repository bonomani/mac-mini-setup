from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TicRunnerAndSummaryTests(unittest.TestCase):
    def test_tic_runner_preserves_empty_requires_status_field(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verify_yaml = tmp_path / "verify.yaml"
            verify_yaml.write_text(
                textwrap.dedent(
                    """\
                    tests:
                      - name: parse-check
                        component: dev-tools
                        intent: "intent survives empty requires_status_target"
                        oracle: "true"
                        trace: "component:dev-tools / smoke"
                    """
                ),
                encoding="utf-8",
            )

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOST_PLATFORM=macos
                        source "{ROOT / 'lib/utils.sh'}"
                        source "{ROOT / 'lib/tic.sh'}"
                        source "{ROOT / 'lib/tic_runner.sh'}"
                        run_tic_tests_from_yaml "{ROOT}" "{verify_yaml}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[pass    ] parse-check", result.stdout)

    def test_summary_prints_capability_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            profile_file = tmp_path / "profile.txt"
            profile_file.write_text("capability|ok\nruntime|ok\n", encoding="utf-8")

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export ARIA_QUEUE_DIR="{tmp_path / 'state'}"
                        export UCC_PROFILE_SUMMARY_FILE="{profile_file}"
                        source "{ROOT / 'lib/ucc.sh'}"
                        source "{ROOT / 'lib/summary.sh'}"
                        init_summary_counters
                        while IFS='|' read -r _profile _outcome; do
                          profile_bump "$_profile" "$_outcome"
                        done < "$UCC_PROFILE_SUMMARY_FILE"
                        for profile in "${{_summary_profiles[@]}}"; do
                          printf '%s\\n' "$(ucc_profile_label "$profile")"
                        done
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("Capability", result.stdout)

    def test_summary_profile_contracts_no_longer_include_presence(self) -> None:
        result = subprocess.run(
            [
                "bash",
                "-lc",
                textwrap.dedent(
                    f"""\
                    set -euo pipefail
                    source "{ROOT / 'lib/ucc.sh'}"
                    source "{ROOT / 'lib/summary.sh'}"
                    print_profile_contracts
                    """
                ),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertNotIn("Profile Presence", result.stdout)
        self.assertIn("Profile Configured", result.stdout)

    def test_summary_prints_uic_and_tic_contract_lines(self) -> None:
        result = subprocess.run(
            [
                "bash",
                "-lc",
                textwrap.dedent(
                    f"""\
                    set -euo pipefail
                    source "{ROOT / 'lib/ucc.sh'}"
                    source "{ROOT / 'lib/summary.sh'}"
                    print_layer_contracts
                    """
                ),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("UIC Gates", result.stdout)
        self.assertIn("TIC Verification", result.stdout)

    def test_tic_runner_supports_conditional_skip_when(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            verify_yaml = tmp_path / "verify.yaml"
            status_file = tmp_path / "status.txt"
            verify_yaml.write_text(
                textwrap.dedent(
                    """\
                    tests:
                      - name: conditional-skip
                        component: ai-python-stack
                        intent: "skip on MPS hosts"
                        oracle: "false"
                        trace: "component:ai-python-stack / smoke"
                        skip: "skip on mps hosts"
                        skip_when: '_tic_target_status_is "mps-available" "ok"'
                    """
                ),
                encoding="utf-8",
            )
            status_file.write_text("mps-available|ok\n", encoding="utf-8")

            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOST_PLATFORM=macos
                        export UCC_TARGET_STATUS_FILE="{status_file}"
                        source "{ROOT / 'lib/utils.sh'}"
                        source "{ROOT / 'lib/tic.sh'}"
                        source "{ROOT / 'lib/tic_runner.sh'}"
                        run_tic_tests_from_yaml "{ROOT}" "{verify_yaml}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[skip    ] conditional-skip", result.stdout)
            self.assertIn("skip on mps hosts", result.stdout)


if __name__ == "__main__":
    unittest.main()
