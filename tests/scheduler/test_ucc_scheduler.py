from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
QUERY = ROOT / "tools" / "validate_targets_manifest.py"


class UccSchedulerTests(unittest.TestCase):
    def _write_manifest(self, root: Path, body: str) -> Path:
        manifest = root / "ucc" / "software"
        manifest.mkdir(parents=True, exist_ok=True)
        path = manifest / "fake.yaml"
        path.write_text(body, encoding="utf-8")
        return root / "ucc"

    def test_manifest_orders_component_targets_topologically(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ucc_dir = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    targets:
                      c:
                        component: fake
                        profile: configured
                        type: config
                        depends_on:
                          - b
                      a:
                        component: fake
                        profile: configured
                        type: config
                      b:
                        component: fake
                        profile: configured
                        type: config
                        depends_on:
                          - a
                    """
                ),
            )
            output = subprocess.check_output(
                ["python3", str(QUERY), "--ordered-targets", "fake", str(ucc_dir)],
                text=True,
            ).strip().splitlines()
            self.assertEqual(output, ["a", "b", "c"])

    def test_registered_targets_execute_in_topological_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    targets:
                      c:
                        component: fake
                        profile: configured
                        type: config
                        depends_on:
                          - b
                      a:
                        component: fake
                        profile: configured
                        type: config
                      b:
                        component: fake
                        profile: configured
                        type: config
                        depends_on:
                          - a
                    """
                ),
            )
            order_file = tmp_path / "order.txt"
            state_dir = tmp_path / "state"
            state_dir.mkdir()
            status_file = tmp_path / "status.txt"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export ARIA_QUEUE_DIR="{state_dir}"
                        export UCC_TARGET_DEFER=1
                        export UCC_TARGETS_MANIFEST="{ucc_dir}"
                        export UCC_TARGETS_QUERY_SCRIPT="{QUERY}"
                        export UCC_TARGET_STATUS_FILE="{status_file}"
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        obs_a() {{ [[ -f "{tmp_path / 'a.done'}" ]] && ucc_asm_config_state configured || ucc_asm_config_state absent; }}
                        obs_b() {{ [[ -f "{tmp_path / 'b.done'}" ]] && ucc_asm_config_state configured || ucc_asm_config_state absent; }}
                        obs_c() {{ [[ -f "{tmp_path / 'c.done'}" ]] && ucc_asm_config_state configured || ucc_asm_config_state absent; }}
                        ins_a() {{ echo a >> "{order_file}"; touch "{tmp_path / 'a.done'}"; }}
                        ins_b() {{ echo b >> "{order_file}"; touch "{tmp_path / 'b.done'}"; }}
                        ins_c() {{ echo c >> "{order_file}"; touch "{tmp_path / 'c.done'}"; }}

                        ucc_reset_registered_targets
                        ucc_target_nonruntime --name c --observe obs_c --install ins_c
                        ucc_target_nonruntime --name a --observe obs_a --install ins_a
                        ucc_target_nonruntime --name b --observe obs_b --install ins_b
                        ucc_flush_registered_targets fake
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(order_file.read_text(encoding="utf-8").splitlines(), ["a", "b", "c"])

    def test_missing_declared_dependency_raises_execution_error(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    targets:
                      a:
                        component: fake
                        profile: configured
                        type: config
                      b:
                        component: fake
                        profile: configured
                        type: config
                        depends_on:
                          - a
                    """
                ),
            )
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_TARGET_DEFER=1
                        export UCC_TARGETS_MANIFEST="{ucc_dir}"
                        export UCC_TARGETS_QUERY_SCRIPT="{QUERY}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        obs_b() {{ ucc_asm_config_state absent; }}
                        ins_b() {{ :; }}

                        ucc_reset_registered_targets
                        ucc_target_nonruntime --name b --observe obs_b --install ins_b
                        ucc_flush_registered_targets fake
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("declared dependency unresolved", result.stdout)
