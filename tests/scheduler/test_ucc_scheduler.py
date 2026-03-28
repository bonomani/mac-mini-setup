from __future__ import annotations

import os
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
                        state_model: config
                        display_name: Config C
                        depends_on:
                          - b
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
                      a:
                        component: fake
                        profile: configured
                        type: config
                        state_model: config
                        display_name: Config A
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
                      b:
                        component: fake
                        profile: configured
                        type: config
                        state_model: config
                        display_name: Config B
                        depends_on:
                          - a
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
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
                        state_model: config
                        display_name: Config C
                        depends_on:
                          - b
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
                      a:
                        component: fake
                        profile: configured
                        type: config
                        state_model: config
                        display_name: Config A
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
                      b:
                        component: fake
                        profile: configured
                        type: config
                        state_model: config
                        display_name: Config B
                        depends_on:
                          - a
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
                    """
                ),
            )
            order_file = tmp_path / "order.txt"
            app_marker = tmp_path / "app.done"
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

    def test_soft_dependencies_influence_order_without_becoming_blocking(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      capability:
                        component: fake
                        profile: capability
                        type: capability
                        runtime_manager: capability
                        probe_kind: command
                        oracle:
                          runtime: "true"
                      app:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake App
                        soft_depends_on:
                          - capability
                        driver:
                          kind: custom-daemon
                        runtime_manager: custom
                        probe_kind: command
                        oracle:
                          runtime: "true"
                        evidence:
                          version: "printf 1.0.0"
                    """
                ),
            )
            ordered = subprocess.check_output(
                ["python3", str(QUERY), "--ordered-targets", "fake", str(ucc_dir)],
                text=True,
            ).strip().splitlines()
            self.assertEqual(ordered, ["capability", "app"])

            order_file = tmp_path / "order.txt"
            app_marker = tmp_path / "app.done"
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

                        obs_app() {{ [[ -f "{app_marker}" ]] && ucc_asm_runtime_desired || ucc_asm_state --installation Absent --runtime NeverStarted --health Unavailable --admin Enabled --dependencies DepsUnknown; }}
                        ins_app() {{ echo app >> "{order_file}"; touch "{app_marker}"; }}

                        ucc_reset_registered_targets
                        ucc_target_service --name app --observe obs_app --install ins_app
                        ucc_flush_registered_targets fake
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(order_file.read_text(encoding="utf-8").splitlines(), ["app"])

    def test_runtime_endpoints_query_reads_nested_endpoint_records(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ucc_dir = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    probe_host: 127.0.0.1
                    probe_port: 9999
                    targets:
                      fake-package:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Fake Package
                        provided_by_tool: fake
                        driver:
                          kind: brew-formula
                        observe_cmd: "printf present"
                        evidence:
                          version: "printf 1.0.0"
                        actions:
                          install: "true"
                          update: "true"
                      fake-runtime:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake Runtime
                        depends_on:
                          - fake-package
                        driver:
                          kind: brew-service
                        runtime_manager: brew-service
                        probe_kind: http
                        oracle:
                          runtime: "curl -fsS http://${probe_host}:${probe_port} >/dev/null 2>&1"
                        evidence:
                          version: "printf 1.0.0"
                        endpoints:
                          - name: Fake API
                            url: http://${probe_host}:${probe_port}
                            note: primary
                    """
                ),
            )
            output = subprocess.check_output(
                ["python3", str(QUERY), "--runtime-endpoints", str(ucc_dir)],
                text=True,
            ).strip()
            self.assertEqual(output, "fake-runtime\tFake API\thttp://127.0.0.1:9999\tprimary")

    def test_display_name_query_reads_target_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ucc_dir = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      fake-runtime:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake Runtime
                        driver:
                          kind: custom-daemon
                        runtime_manager: custom
                        probe_kind: command
                        oracle:
                          runtime: "true"
                        evidence:
                          version: "printf 1.0.0"
                    """
                ),
            )
            output = subprocess.check_output(
                ["python3", str(QUERY), "--display-name", "fake-runtime", str(ucc_dir)],
                text=True,
            ).strip()
            self.assertEqual(output, "Fake Runtime")

    def test_yaml_simple_target_executes_manifest_declared_commands(self) -> None:
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
                      simple:
                        component: fake
                        profile: configured
                        type: config
                        state_model: config
                        driver:
                          kind: shell-file-edit
                        oracle:
                          configured: '[[ -f "$HOME/simple.txt" ]]'
                        evidence:
                          path: 'printf "%s" "$HOME/simple.txt"'
                        actions:
                          install: |
                            touch "$HOME/simple.txt"
                    """
                ),
            )
            home_dir = tmp_path / "home"
            home_dir.mkdir()
            state_dir = tmp_path / "state"
            state_dir.mkdir()
            status_file = tmp_path / "status.txt"
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOME="{home_dir}"
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

                        ucc_reset_registered_targets
                        ucc_yaml_simple_target "{ROOT}" "{manifest}" simple
                        ucc_flush_registered_targets fake
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertTrue((home_dir / "simple.txt").exists())

    def test_yaml_simple_target_supports_dotted_target_names_and_target_local_scalars(self) -> None:
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
                      pkg.with.dot:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Demo package
                        provided_by_tool: fake
                        driver:
                          kind: fake
                          ref: demo
                        observe_cmd: '[[ -f "$HOME/demo.txt" ]] && printf "%s" "${driver.ref}" || printf absent'
                        evidence:
                          version: 'printf "%s" "${driver.ref}"'
                        actions:
                          install: |
                            touch "$HOME/demo.txt"
                    """
                ),
            )
            home_dir = tmp_path / "home"
            home_dir.mkdir()
            state_dir = tmp_path / "state"
            state_dir.mkdir()
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOME="{home_dir}"
                        export ARIA_QUEUE_DIR="{state_dir}"
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

                        ucc_reset_registered_targets
                        ucc_yaml_simple_target "{ROOT}" "{manifest}" "pkg.with.dot"
                        ucc_flush_registered_targets fake
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertTrue((home_dir / "demo.txt").exists())

    def test_read_config_get_many_returns_multiple_scalar_rows(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    api_host: 127.0.0.1
                    api_port: 9999
                    endpoint_url: http://${api_host}:${api_port}
                    targets: {}
                    """
                ),
            ) / "software" / "fake.yaml"
            rows = subprocess.check_output(
                [
                    "python3",
                    str(ROOT / "tools" / "read_config.py"),
                    "--get-many",
                    str(manifest),
                    "api_host",
                    "endpoint_url",
                ],
                text=True,
            ).strip("\0").split("\0")
            self.assertEqual(rows, ["api_host\t127.0.0.1", "endpoint_url\thttp://127.0.0.1:9999"])

    def test_read_config_target_get_many_substitutes_target_scalars(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    root_dir: demo
                    targets:
                      pkg:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        provided_by_tool: fake
                        driver:
                          kind: brew-formula
                          ref: demo
                        observe_cmd: "printf '%s' '${driver.ref}'"
                        evidence:
                          version: "printf '%s' '${driver.ref}'"
                        actions:
                          install: "printf '%s/%s' '${root_dir}' '${driver.ref}'"
                    """
                ),
            ) / "software" / "fake.yaml"
            rows = subprocess.check_output(
                [
                    "python3",
                    str(ROOT / "tools" / "read_config.py"),
                    "--target-get-many",
                    str(manifest),
                    "pkg",
                    "observe_cmd",
                    "actions.install",
                ],
                text=True,
            ).strip("\0").split("\0")
            self.assertEqual(rows, ["observe_cmd\tprintf '%s' 'demo'", "actions.install\tprintf '%s/%s' 'demo' 'demo'"])

    def test_yaml_simple_target_handles_multiline_observe_cmd_after_batched_lookup(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            marker = tmp_path / "installed.txt"
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    f"""\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    targets:
                      pkg:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Fake Package
                        provided_by_tool: fake
                        driver:
                          kind: fake
                        observe_cmd: |
                          if [[ -f "{marker}" ]]; then
                            printf '1.2.3'
                          else
                            printf 'absent'
                          fi
                        evidence:
                          version: |
                            if [[ -f "{marker}" ]]; then
                              printf '1.2.3'
                            fi
                        actions:
                          install: 'touch "{marker}"'
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        export UCC_TARGETS_MANIFEST="{ucc_dir}"
                        export UCC_TARGETS_QUERY_SCRIPT="{QUERY}"
                        source "{ROOT / 'lib/ucc.sh'}"

                        ucc_yaml_simple_target "{ROOT}" "{manifest}" pkg
                        ucc_yaml_simple_target "{ROOT}" "{manifest}" pkg
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[installed] pkg", result.stdout)
            self.assertIn("version=1.2.3", result.stdout)

    def test_xcode_command_line_tools_reports_outdated_when_softwareupdate_lists_update(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            (fake_bin / "xcode-select").write_text(
                "#!/bin/bash\n"
                "if [[ \"$1\" == \"-p\" ]]; then\n"
                "  printf '/Library/Developer/CommandLineTools\\n'\n"
                "  exit 0\n"
                "fi\n"
                "exit 1\n",
                encoding="utf-8",
            )
            (fake_bin / "softwareupdate").write_text(
                "#!/bin/bash\n"
                "cat <<'EOF'\n"
                "Software Update Tool\n"
                "\n"
                "Finding available software\n"
                "Software Update found the following new or updated software:\n"
                "* Label: Command Line Tools for Xcode-16.4\n"
                "  Title: Command Line Tools for Xcode, Version: 16.4, Size: 942384KiB, Recommended: YES,\n"
                "EOF\n",
                encoding="utf-8",
            )
            os.chmod(fake_bin / "xcode-select", 0o755)
            os.chmod(fake_bin / "softwareupdate", 0o755)
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export PATH="{fake_bin}:$PATH"
                        source "{ROOT / 'lib/utils.sh'}"
                        source "{ROOT / 'lib/ucc_asm.sh'}"
                        source "{ROOT / 'lib/ucc_targets.sh'}"
                        _ucc_observe_yaml_simple_target "{ROOT}" "{ROOT / 'ucc/software/homebrew.yaml'}" "xcode-command-line-tools"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn('"installation_state":"Installed"', result.stdout)
            self.assertIn('"health_state":"Degraded"', result.stdout)

    def test_xcode_command_line_tools_uses_update_action_when_outdated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            fake_bin = tmp_path / "bin"
            fake_bin.mkdir()
            (fake_bin / "xcode-select").write_text(
                "#!/bin/bash\n"
                "if [[ \"$1\" == \"-p\" ]]; then\n"
                "  printf '/Library/Developer/CommandLineTools\\n'\n"
                "  exit 0\n"
                "fi\n"
                "if [[ \"$1\" == \"--install\" ]]; then\n"
                "  printf 'unexpected install\\n' >&2\n"
                "  exit 9\n"
                "fi\n"
                "exit 1\n",
                encoding="utf-8",
            )
            (fake_bin / "softwareupdate").write_text(
                "#!/bin/bash\n"
                "cat <<'EOF'\n"
                "Software Update found the following new or updated software:\n"
                "* Label: Command Line Tools for Xcode-16.4\n"
                "  Title: Command Line Tools for Xcode, Version: 16.4, Size: 942384KiB, Recommended: YES,\n"
                "EOF\n",
                encoding="utf-8",
            )
            (fake_bin / "pkgutil").write_text(
                "#!/bin/bash\n"
                "printf 'package-id: com.apple.pkg.CLTools_Executables\\nversion: 26.3.0.0.1.1771626560\\n'\n",
                encoding="utf-8",
            )
            os.chmod(fake_bin / "xcode-select", 0o755)
            os.chmod(fake_bin / "softwareupdate", 0o755)
            os.chmod(fake_bin / "pkgutil", 0o755)
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export PATH="{fake_bin}:$PATH"
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"
                        ucc_yaml_simple_target "{ROOT}" "{ROOT / 'ucc/software/homebrew.yaml'}" "xcode-command-line-tools"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("update error was=", result.stdout)
            self.assertNotIn("Triggering Xcode Command Line Tools install", result.stdout)

    def test_manifest_validation_rejects_non_string_display_name(self) -> None:
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
                      bad:
                        component: fake
                        profile: configured
                        type: config
                        display_name:
                          nested: nope
                    """
                ),
            )
            result = subprocess.run(
                ["python3", str(QUERY), str(ucc_dir)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("field 'display_name' must be a non-empty string", result.stderr)

    def test_manifest_validation_rejects_sparse_generated_targets(self) -> None:
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
                      vscode-ext-test.example:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        depends_on:
                          - vscode-code-cmd
                      vscode-code-cmd:
                        component: fake
                        profile: configured
                        type: config
                        state_model: config
                    vscode_extensions:
                      - vscode-ext-test.example
                    """
                ),
            )
            result = subprocess.run(
                ["python3", str(QUERY), str(ucc_dir)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("generated target 'vscode-ext-test.example' in section 'vscode_extensions' requires provided_by_tool", result.stderr)

    def test_manifest_validation_rejects_sparse_cli_generated_targets(self) -> None:
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
                      homebrew:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                      cli-fake:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        depends_on:
                          - homebrew
                    cli_tools:
                      - cli-fake
                    """
                ),
            )
            result = subprocess.run(
                ["python3", str(QUERY), str(ucc_dir)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("generated target 'cli-fake' in section 'cli_tools' requires provided_by_tool", result.stderr)

    def test_yaml_capability_target_uses_runtime_oracle_and_yaml_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      cap:
                        component: fake
                        profile: capability
                        type: capability
                        display_name: Fake Capability
                        runtime_manager: capability
                        probe_kind: command
                        oracle:
                          runtime: "true"
                        evidence:
                          gpu: "printf TestGPU"
                          status: "printf available"
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        export UCC_TARGETS_MANIFEST="{ucc_dir}"
                        export UCC_TARGETS_QUERY_SCRIPT="{QUERY}"
                        source "{ROOT / 'lib/ucc.sh'}"

                        ucc_yaml_capability_target "{ROOT}" "{manifest}" cap
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[ok      ] Fake Capability", result.stdout)
            self.assertIn("gpu=TestGPU", result.stdout)
            self.assertIn("status=available", result.stdout)

    def test_yaml_parametric_target_uses_observe_cmd_and_desired_value(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: parametric
                    libs: fake
                    runner: run_fake
                    targets:
                      setting:
                        component: fake
                        profile: parametric
                        type: config
                        state_model: parametric
                        driver:
                          kind: shell-file-edit
                        observe_cmd: '[[ -f "$HOME/setting.applied" ]] && printf on || printf off'
                        desired_value: 'on'
                        evidence:
                          mode: '[[ -f "$HOME/setting.applied" ]] && printf on || printf off'
                        actions:
                          install: 'touch "$HOME/setting.applied"'
                          update: 'touch "$HOME/setting.applied"'
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            home_dir = tmp_path / "home"
            home_dir.mkdir()
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOME="{home_dir}"
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        ucc_yaml_parametric_target "{ROOT}" "{manifest}" setting
                        ucc_yaml_parametric_target "{ROOT}" "{manifest}" setting
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[updated ] setting", result.stdout)
            self.assertIn("mode=on", result.stdout)
            self.assertTrue((home_dir / "setting.applied").exists())

    def test_validator_requires_state_model_for_package_targets(self) -> None:
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
                      pkg:
                        component: fake
                        profile: configured
                        type: package
                    """
                ),
            )
            result = subprocess.run(
                ["python3", str(QUERY), str(ucc_dir)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("type 'package' requires state_model 'package'", result.stderr)

    def test_validator_enforces_canonical_target_key_order(self) -> None:
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
                      pkg:
                        component: fake
                        profile: configured
                        type: package
                        oracle:
                          configured: "true"
                        state_model: package
                    """
                ),
            )
            result = subprocess.run(
                ["python3", str(QUERY), str(ucc_dir)],
                text=True,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("keys must follow canonical order", result.stderr)

    def test_yaml_parametric_target_supports_desired_cmd_and_yaml_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: parametric
                    libs: fake
                    runner: run_fake
                    targets:
                      setting:
                        component: fake
                        profile: parametric
                        type: config
                        state_model: parametric
                        driver:
                          kind: shell-file-edit
                        observe_cmd: '[[ -f "$HOME/setting.applied" ]] && printf "mode=%s" "$TEST_SETTING_MODE" || printf "mode=off"'
                        desired_cmd: 'printf "mode=%s" "$TEST_SETTING_MODE"'
                        evidence:
                          mode: '[[ -f "$HOME/setting.applied" ]] && printf "%s" "$TEST_SETTING_MODE" || printf off'
                        actions:
                          install: 'touch "$HOME/setting.applied"'
                          update: 'touch "$HOME/setting.applied"'
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            home_dir = tmp_path / "home"
            home_dir.mkdir()
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOME="{home_dir}"
                        export TEST_SETTING_MODE="on"
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        ucc_yaml_parametric_target "{ROOT}" "{manifest}" setting
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[updated ] setting", result.stdout)
            self.assertIn("mode=on", result.stdout)
            self.assertTrue((home_dir / "setting.applied").exists())

    def test_yaml_parametric_target_reuses_install_cmd_for_update_when_update_cmd_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: parametric
                    libs: fake
                    runner: run_fake
                    targets:
                      setting:
                        component: fake
                        profile: parametric
                        type: config
                        state_model: parametric
                        driver:
                          kind: shell-file-edit
                        observe_cmd: 'printf off'
                        desired_value: 'on'
                        actions:
                          install: 'printf updated > "$HOME/update.txt"'
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            home_dir = tmp_path / "home"
            home_dir.mkdir()
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOME="{home_dir}"
                        export UCC_MODE=update
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        ucc_yaml_parametric_target "{ROOT}" "{manifest}" setting
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertTrue((home_dir / "update.txt").exists())

    def test_yaml_runtime_target_uses_yaml_oracles_and_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      app:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: App
                        driver:
                          kind: custom-daemon
                        runtime_manager: custom
                        probe_kind: command
                        oracle:
                          configured: '[[ -f "$HOME/app.installed" ]]'
                          runtime: '[[ -f "$HOME/app.ready" ]]'
                        evidence:
                          version: 'printf 1.2.3'
                        stopped_health: Unavailable
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            home_dir = tmp_path / "home"
            home_dir.mkdir()
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOME="{home_dir}"
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        install_app() {{ touch "$HOME/app.installed" "$HOME/app.ready"; }}
                        ucc_yaml_runtime_target "{ROOT}" "{manifest}" app install_app install_app
                        ucc_yaml_runtime_target "{ROOT}" "{manifest}" app install_app install_app
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[installed] app", result.stdout)
            self.assertIn("version=1.2.3", result.stdout)

    def test_read_config_records_substitutes_top_level_scalars(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    probe_host: 127.0.0.1
                    probe_port: 9999
                    targets:
                      fake-runtime:
                        component: fake
                        profile: runtime
                        type: runtime
                        driver:
                          kind: docker-compose
                        endpoints:
                          - name: Fake API
                            url: http://${probe_host}:${probe_port}
                            note: primary
                    """
                ),
            ) / "software" / "fake.yaml"
            output = subprocess.check_output(
                [
                    "python3",
                    str(ROOT / "tools" / "read_config.py"),
                    "--records",
                    str(manifest),
                    "targets.fake-runtime.endpoints",
                    "name",
                    "url",
                    "note",
                ],
                text=True,
            ).strip()
            self.assertEqual(output, "Fake API\thttp://127.0.0.1:9999\tprimary")

    def test_read_config_get_substitutes_top_level_scalars(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    probe_port: 9999
                    targets:
                      fake-runtime:
                        component: fake
                        profile: runtime
                        type: runtime
                        driver:
                          kind: custom-daemon
                        oracle:
                          runtime: 'curl -fsS http://127.0.0.1:${probe_port} >/dev/null 2>&1'
                    """
                ),
            ) / "software" / "fake.yaml"
            output = subprocess.check_output(
                ["python3", str(ROOT / "tools" / "read_config.py"), "--get", str(manifest), "targets.fake-runtime.oracle.runtime"],
                text=True,
            ).strip()
            self.assertEqual(output, 'curl -fsS http://127.0.0.1:9999 >/dev/null 2>&1')

    def test_read_config_target_get_substitutes_target_local_scalars(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            manifest = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    targets:
                      pkg.with.dot:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        provided_by_tool: fake
                        driver:
                          kind: brew-formula
                          ref: demo
                        observe_cmd: "printf '%s' '${driver.ref}'"
                        evidence:
                          version: "printf '%s' '${driver.ref}'"
                        actions:
                          install: "printf '%s' '${driver.ref}'"
                    """
                ),
            ) / "software" / "fake.yaml"
            observe_cmd = subprocess.check_output(
                ["python3", str(ROOT / "tools" / "read_config.py"), "--target-get", str(manifest), "pkg.with.dot", "observe_cmd"],
                text=True,
            ).strip()
            install_cmd = subprocess.check_output(
                ["python3", str(ROOT / "tools" / "read_config.py"), "--target-get", str(manifest), "pkg.with.dot", "actions.install"],
                text=True,
            ).strip()
            evidence = subprocess.check_output(
                ["python3", str(ROOT / "tools" / "read_config.py"), "--evidence", str(manifest), "pkg.with.dot"],
                text=True,
            ).strip("\0")
            self.assertEqual(observe_cmd, "printf '%s' 'demo'")
            self.assertEqual(install_cmd, "printf '%s' 'demo'")
            self.assertEqual(evidence, "version\tprintf '%s' 'demo'")

    def test_brew_cached_version_works_with_driver_ref_substitution(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            manifest = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    targets:
                      pkg:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Demo package
                        provided_by_tool: brew
                        driver:
                          kind: brew-formula
                          ref: demo
                        observe_cmd: "printf present"
                        evidence:
                          version: "_brew_cached_version '${driver.ref}'"
                        actions:
                          install: "true"
                    """
                ),
            ) / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        source "{ROOT / 'lib/utils.sh'}"
                        source "{ROOT / 'lib/ucc_brew.sh'}"
                        source "{ROOT / 'lib/ucc_targets.sh'}"
                        export _BREW_VERSIONS_CACHE=$'demo 1.2.3\\nother 9.9.9'
                        ucc_eval_evidence_from_yaml "{ROOT}" "{manifest}" pkg
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip(), "version=1.2.3")

    def test_brew_observe_uses_version_cache_in_install_only_mode(self) -> None:
        result = subprocess.run(
            [
                "bash",
                "-lc",
                textwrap.dedent(
                    f"""\
                    set -euo pipefail
                    source "{ROOT / 'lib/utils.sh'}"
                    source "{ROOT / 'lib/ucc_brew.sh'}"
                    export UIC_PREF_PACKAGE_UPDATE_POLICY=install-only
                    export _BREW_VERSIONS_CACHE=$'demo 1.2.3\\nother 9.9.9'
                    export _BREW_CASK_VERSIONS_CACHE=$'demo-cask 4.5.6'
                    printf '%s\\n' "$(brew_observe demo)"
                    printf '%s\\n' "$(brew_cask_observe demo-cask)"
                    """
                ),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(result.stdout.strip().splitlines(), ["1.2.3", "4.5.6"])

    def test_brew_refresh_caches_dispatches_by_update_policy(self) -> None:
        result = subprocess.run(
            [
                "bash",
                "-lc",
                textwrap.dedent(
                    """\
                    set -euo pipefail
                    source "lib/ucc_brew.sh"
                    brew_cache_versions() { echo versions; }
                    brew_cache_outdated() { echo outdated; }
                    export UIC_PREF_PACKAGE_UPDATE_POLICY=install-only
                    brew_refresh_caches
                    export UIC_PREF_PACKAGE_UPDATE_POLICY=always-upgrade
                    brew_refresh_caches
                    """
                ),
            ],
            text=True,
            capture_output=True,
            cwd=str(ROOT),
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(result.stdout.strip().splitlines(), ["versions", "outdated"])

    def test_brew_cask_observe_supports_greedy_auto_updates_cache(self) -> None:
        result = subprocess.run(
            [
                "bash",
                "-lc",
                textwrap.dedent(
                    f"""\
                    set -euo pipefail
                    source "{ROOT / 'lib/utils.sh'}"
                    source "{ROOT / 'lib/ucc_brew.sh'}"
                    export UIC_PREF_PACKAGE_UPDATE_POLICY=always-upgrade
                    export _BREW_CASK_VERSIONS_CACHE=$'lm-studio 0.4.7'
                    export _BREW_CASK_OUTDATED_CACHE=''
                    export _BREW_CASK_OUTDATED_GREEDY_AUTO_UPDATES_CACHE='lm-studio'
                    printf '%s\\n' "$(brew_cask_observe lm-studio)"
                    printf '%s\\n' "$(brew_cask_observe lm-studio true)"
                    """
                ),
            ],
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(result.stdout.strip().splitlines(), ["0.4.7", "outdated"])

    def test_brew_cask_upgrade_uses_greedy_auto_updates_when_requested(self) -> None:
        result = subprocess.run(
            [
                "bash",
                "-lc",
                textwrap.dedent(
                    """\
                    set -euo pipefail
                    source "lib/utils.sh"
                    source "lib/ucc_brew.sh"
                    ucc_run() { printf '%s\n' "$*"; }
                    brew_refresh_caches() { :; }
                    brew_cask_upgrade lm-studio true
                    brew_cask_upgrade iterm2 false
                    """
                ),
            ],
            text=True,
            capture_output=True,
            cwd=str(ROOT),
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertEqual(
            result.stdout.strip().splitlines(),
            [
                "brew upgrade --cask --greedy-auto-updates lm-studio",
                "brew upgrade --cask iterm2",
            ],
        )

    def test_pip_cached_version_works_with_driver_ref_substitution(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            manifest = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    targets:
                      pkg:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Demo package
                        provided_by_tool: pip
                        driver:
                          kind: pip
                          ref: demo-pkg
                        observe_cmd: "printf present"
                        evidence:
                          version: "_pip_cached_version '${driver.ref}'"
                        actions:
                          install: "true"
                    """
                ),
            ) / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        source "{ROOT / 'lib/utils.sh'}"
                        source "{ROOT / 'lib/ucc_targets.sh'}"
                        export _PIP_VERSIONS_CACHE='[{{"name":"demo-pkg","version":"4.5.6"}},{{"name":"other","version":"0.1.0"}}]'
                        ucc_eval_evidence_from_yaml "{ROOT}" "{manifest}" pkg
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip(), "version=4.5.6")

    def test_vscode_extension_cache_avoids_repeated_code_calls(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            counter = Path(tmp) / "count.txt"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        printf '0' > "{counter}"
                        source "{ROOT / 'lib/utils.sh'}"
                        code() {{
                          local count
                          count="$(cat "{counter}")"
                          printf '%s' "$((count + 1))" > "{counter}"
                          cat <<'EOF'
                        ms-python.python@2026.4.0
                        eamodio.gitlens@17.11.1
                        EOF
                        }}
                        vscode_extensions_cache_versions
                        printf '%s\\n' "$(_vscode_extension_cached_version ms-python.python)"
                        printf '%s\\n' "$(_vscode_extension_cached_version ms-python.python)"
                        cat "{counter}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["2026.4.0", "2026.4.0", "1"])

    def test_npm_global_cache_avoids_repeated_npm_calls(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            counter = Path(tmp) / "count.txt"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        printf '0' > "{counter}"
                        source "{ROOT / 'lib/utils.sh'}"
                        npm() {{
                          local count
                          count="$(cat "{counter}")"
                          printf '%s' "$((count + 1))" > "{counter}"
                          cat <<'EOF'
                        {{"dependencies":{{"@openai/codex":{{"version":"0.116.0"}},"bmad-method":{{"version":"6.2.0"}}}}}}
                        EOF
                        }}
                        npm_global_cache_versions
                        printf '%s\\n' "$(npm_global_version '@openai/codex')"
                        printf '%s\\n' "$(npm_global_version '@openai/codex')"
                        cat "{counter}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["0.116.0", "0.116.0", "1"])

    def test_ollama_model_cache_avoids_repeated_ollama_list_calls(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            counter = Path(tmp) / "count.txt"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        printf '0' > "{counter}"
                        source "{ROOT / 'lib/utils.sh'}"
                        ollama() {{
                          local count
                          count="$(cat "{counter}")"
                          printf '%s' "$((count + 1))" > "{counter}"
                          cat <<'EOF'
                        NAME              ID      SIZE      MODIFIED
                        llama3.2          abc123  2.0 GB    now
                        nomic-embed-text  def456  274 MB    now
                        EOF
                        }}
                        ollama_model_cache_list
                        if ollama_model_present llama3.2; then printf 'yes\\n'; else printf 'no\\n'; fi
                        if ollama_model_present llama3.2; then printf 'yes\\n'; else printf 'no\\n'; fi
                        cat "{counter}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["yes", "yes", "1"])

    def test_vscode_extension_install_refreshes_cache_after_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            counter = tmp_path / "count.txt"
            marker = tmp_path / "ext.installed"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        printf '0' > "{counter}"
                        source "{ROOT / 'lib/utils.sh'}"
                        ucc_run() {{ "$@"; }}
                        code() {{
                          if [[ "$1" == --list-extensions ]]; then
                            local count
                            count="$(cat "{counter}")"
                            printf '%s' "$((count + 1))" > "{counter}"
                            if [[ -f "{marker}" ]]; then
                              printf '%s\\n' 'ms-python.python@2026.4.0'
                            fi
                            return 0
                          fi
                          if [[ "$1" == --install-extension ]]; then
                            touch "{marker}"
                            return 0
                          fi
                          return 1
                        }}
                        vscode_extensions_cache_versions
                        value="$(_vscode_extension_cached_version ms-python.python)"
                        printf '%s\\n' "${{value:-missing}}"
                        vscode_extension_install ms-python.python
                        value="$(_vscode_extension_cached_version ms-python.python)"
                        printf '%s\\n' "${{value:-missing}}"
                        cat "{counter}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["missing", "2026.4.0", "2"])

    def test_npm_global_install_refreshes_cache_after_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            counter = tmp_path / "count.txt"
            marker = tmp_path / "pkg.installed"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        printf '0' > "{counter}"
                        source "{ROOT / 'lib/utils.sh'}"
                        ucc_run() {{ "$@"; }}
                        npm() {{
                          if [[ "$1" == ls ]]; then
                            local count
                            count="$(cat "{counter}")"
                            printf '%s' "$((count + 1))" > "{counter}"
                            if [[ -f "{marker}" ]]; then
                              cat <<'EOF'
                        {{"dependencies":{{"@openai/codex":{{"version":"0.116.0"}}}}}}
                        EOF
                            else
                              cat <<'EOF'
                        {{"dependencies":{{}}}}
                        EOF
                            fi
                            return 0
                          fi
                          if [[ "$1" == install && "$2" == -g ]]; then
                            touch "{marker}"
                            return 0
                          fi
                          return 1
                        }}
                        npm_global_cache_versions
                        value="$(npm_global_version '@openai/codex')"
                        printf '%s\\n' "${{value:-missing}}"
                        npm_global_install '@openai/codex'
                        value="$(npm_global_version '@openai/codex')"
                        printf '%s\\n' "${{value:-missing}}"
                        cat "{counter}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["missing", "0.116.0", "2"])

    def test_ollama_model_pull_refreshes_cache_after_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            counter = tmp_path / "count.txt"
            marker = tmp_path / "model.pulled"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        printf '0' > "{counter}"
                        source "{ROOT / 'lib/utils.sh'}"
                        ucc_run() {{ "$@"; }}
                        log_info() {{ :; }}
                        ollama() {{
                          if [[ "$1" == list ]]; then
                            local count
                            count="$(cat "{counter}")"
                            printf '%s' "$((count + 1))" > "{counter}"
                            cat <<'EOF'
                        NAME              ID      SIZE      MODIFIED
                        EOF
                            if [[ -f "{marker}" ]]; then
                              printf '%s\\n' 'llama3.2          abc123  2.0 GB    now'
                            fi
                            return 0
                          fi
                          if [[ "$1" == pull ]]; then
                            touch "{marker}"
                            return 0
                          fi
                          return 1
                        }}
                        ollama_model_cache_list
                        if ollama_model_present llama3.2; then printf 'yes\\n'; else printf 'no\\n'; fi
                        ollama_model_pull llama3.2
                        if ollama_model_present llama3.2; then printf 'yes\\n'; else printf 'no\\n'; fi
                        cat "{counter}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["no", "yes", "2"])

    def test_ai_app_runtime_metadata_cache_avoids_repeated_docker_calls(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            manifest = tmp_path / "ai-apps.yaml"
            manifest.write_text(
                textwrap.dedent(
                    """\
                    component: ai-apps
                    primary_profile: runtime
                    libs: ai_apps
                    runner: run_ai_apps_from_yaml
                    stack:
                      compose_dir: .ai-stack
                      compose_file: docker-compose.yml
                      definition_template: stack/docker-compose.yml
                      marker: '# ai-stack test'
                      services:
                      - open-webui
                    targets:
                      ai-stack-compose-file:
                        component: ai-apps
                        profile: parametric
                        type: config
                        state_model: parametric
                        display_name: compose file
                        driver:
                          kind: compose-file
                        evidence:
                          path: printf '%s' "$COMPOSE_FILE"
                      open-webui-runtime:
                        component: ai-apps
                        profile: runtime
                        type: runtime
                        display_name: Open WebUI
                        depends_on:
                        - docker-desktop
                        - ai-stack-compose-file
                        provided_by_tool: docker-compose
                        driver:
                          kind: docker-compose
                          service_name: open-webui
                        runtime_manager: docker-compose
                        probe_kind: http
                        oracle:
                          runtime: "true"
                        evidence:
                          version: _ai_service_runtime_version '${driver.service_name}'
                          digest: _ai_service_runtime_digest '${driver.service_name}'
                          ref: _ai_service_runtime_ref '${driver.service_name}'
                        actions:
                          install: _ai_apply_compose_runtime
                    """
                ),
                encoding="utf-8",
            )
            service_counter = tmp_path / "service-count.txt"
            image_counter = tmp_path / "image-count.txt"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        printf '0' > "{service_counter}"
                        printf '0' > "{image_counter}"
                        source "{ROOT / 'lib/utils.sh'}"
                        source "{ROOT / 'lib/ucc_targets.sh'}"
                        source "{ROOT / 'lib/ai_apps.sh'}"
                        log_info() {{ :; }}
                        log_warn() {{ :; }}
                        ucc_asm_config_desired() {{ printf '%s' "$1"; }}
                        ucc_target() {{ :; }}
                        ucc_yaml_runtime_target() {{
                          local cfg_dir="$1" yaml="$2" target="$3"
                          ucc_eval_evidence_from_yaml "$cfg_dir" "$yaml" "$target" >/dev/null
                        }}
                        docker() {{
                          if [[ "$1" == info ]]; then
                            return 0
                          fi
                          if [[ "$1" == inspect && "$2" == --format && "$3" == '{{{{.Config.Image}}}}' && "$4" == open-webui ]]; then
                            local count
                            count="$(cat "{service_counter}")"
                            printf '%s' "$((count + 1))" > "{service_counter}"
                            printf '%s\\n' 'ghcr.io/open-webui/open-webui:main'
                            return 0
                          fi
                          if [[ "$1" == image && "$2" == inspect ]]; then
                            local count
                            count="$(cat "{image_counter}")"
                            printf '%s' "$((count + 1))" > "{image_counter}"
                            if [[ "$3" == --format && "$4" == '{{{{ index .Config.Labels \"org.opencontainers.image.version\" }}}}' ]]; then
                              printf '%s\\n' 'main'
                              return 0
                            fi
                            if [[ "$3" == --format && "$4" == '{{{{index .RepoDigests 0}}}}' ]]; then
                              printf '%s\\n' 'ghcr.io/open-webui/open-webui@sha256:1234567890abcdef1234567890abcdef'
                              return 0
                            fi
                            if [[ "$3" == --format && "$4" == '{{{{ index .Config.Labels \"org.label-schema.version\" }}}}' ]]; then
                              printf '%s\\n' '<no value>'
                              return 0
                            fi
                          fi
                          printf 'unexpected docker call: %s\\n' "$*" >&2
                          return 1
                        }}
                        export HOME="{tmp_path / 'home'}"
                        mkdir -p "$HOME"
                        export UIC_PREF_AI_APPS_IMAGE_POLICY=reuse-local
                        export UCC_DRY_RUN=1
                        run_ai_apps_from_yaml "{ROOT}" "{manifest}"
                        printf '%s\\n' "$(cat "{service_counter}")"
                        printf '%s\\n' "$(cat "{image_counter}")"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip().splitlines(), ["1", "1"])

    def test_platform_specific_dependencies_follow_host_variant(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            ucc_dir = self._write_manifest(
                Path(tmp),
                textwrap.dedent(
                    """\
                    component: fake
                    primary_profile: configured
                    libs: fake
                    runner: run_fake
                    platforms:
                      - macos
                      - linux
                      - wsl2
                    platform_tool_preferences:
                      macos:
                        - brew-installer
                      linux:
                        - native-package-manager
                        - brew-installer
                      wsl2:
                        - native-package-manager
                        - brew-installer
                    targets:
                      xcode:
                        component: fake
                        profile: configured
                        type: precondition
                        state_model: config
                        display_name: Xcode
                        driver:
                          kind: platform-check
                        oracle:
                          configured: "true"
                        evidence:
                          state: "printf supported"
                      pkg:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Pkg
                        depends_on_by_platform:
                          macos:
                            - xcode
                        provided_by_tool: fake
                        driver:
                          kind: brew-formula
                        observe_cmd: "printf present"
                        evidence:
                          version: "printf 1.0.0"
                        actions:
                          install: "true"
                          update: "true"
                    """
                ),
            )
            macos_output = subprocess.check_output(
                ["python3", str(QUERY), "--deps", "pkg", str(ucc_dir)],
                text=True,
                env={**os.environ, **{"HOST_PLATFORM": "macos", "HOST_PLATFORM_VARIANT": "macos"}},
            ).strip().splitlines()
            linux_output = subprocess.check_output(
                ["python3", str(QUERY), "--deps", "pkg", str(ucc_dir)],
                text=True,
                env={**os.environ, **{"HOST_PLATFORM": "linux", "HOST_PLATFORM_VARIANT": "linux"}},
            ).strip()
            wsl2_output = subprocess.check_output(
                ["python3", str(QUERY), "--deps", "pkg", str(ucc_dir)],
                text=True,
                env={**os.environ, **{"HOST_PLATFORM": "wsl", "HOST_PLATFORM_VARIANT": "wsl2"}},
            ).strip()
            self.assertEqual(macos_output, ["xcode"])
            self.assertEqual(linux_output, "")
            self.assertEqual(wsl2_output, "")

    def test_brew_runtime_target_uses_yaml_probe_and_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            marker = tmp_path / "runtime.ok"
            marker.write_text("ok", encoding="utf-8")
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    f"""\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      fake-package:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Fake Package
                        provided_by_tool: fake
                        driver:
                          kind: brew-formula
                        observe_cmd: "printf present"
                        evidence:
                          version: "printf 1.2.3"
                        actions:
                          install: "true"
                          update: "true"
                      fake-service:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake Service
                        depends_on:
                          - fake-package
                        driver:
                          kind: brew-service
                        runtime_manager: brew-service
                        probe_kind: command
                        oracle:
                          configured: "true"
                          runtime: '[[ -f "{marker}" ]]'
                        evidence:
                          version: "printf 1.2.3"
                          pid: "printf 4321"
                          listener: "printf tcp:127.0.0.1:9999"
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        brew_observe() {{ printf '1.2.3'; }}
                        _ucc_brew_service_status() {{ printf 'started'; }}

                        ucc_brew_runtime_formula_target "fake-service" "fake" "fake-ref" "{ROOT}" "{manifest}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[ok      ] fake-service", result.stdout)
            self.assertIn("version=1.2.3", result.stdout)
            self.assertIn("pid=4321", result.stdout)
            self.assertIn("listener=tcp:127.0.0.1:9999", result.stdout)

    def test_brew_runtime_target_restarts_started_service_when_probe_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            marker = tmp_path / "runtime.ok"
            commands = tmp_path / "commands.txt"
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    f"""\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      fake-package:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                        display_name: Fake Package
                        provided_by_tool: fake
                        driver:
                          kind: brew-formula
                        observe_cmd: "printf present"
                        evidence:
                          version: "printf 1.2.3"
                        actions:
                          install: "true"
                          update: "true"
                      fake-service:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake Service
                        depends_on:
                          - fake-package
                        driver:
                          kind: brew-service
                        runtime_manager: brew-service
                        probe_kind: command
                        oracle:
                          configured: "true"
                          runtime: '[[ -f "{marker}" ]]'
                        evidence:
                          version: "printf 1.2.3"
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        brew_observe() {{ printf '1.2.3'; }}
                        _ucc_brew_service_status() {{ printf 'started'; }}
                        brew() {{
                          printf '%s\\n' "$*" >> "{commands}"
                          touch "{marker}"
                        }}

                        ucc_brew_runtime_formula_target "fake-service" "fake" "fake-ref" "{ROOT}" "{manifest}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("services restart fake-ref", commands.read_text(encoding="utf-8"))
            self.assertIn("fake-service", result.stdout)

    def test_brew_runtime_target_waits_for_probe_after_start(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            marker = tmp_path / "runtime.ok"
            started = tmp_path / "service.started"
            commands = tmp_path / "commands.txt"
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    f"""\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      fake-package:
                        component: fake
                        profile: configured
                        type: package
                        state_model: package
                      fake-service:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake Service
                        depends_on:
                          - fake-package
                        driver:
                          kind: brew-service
                        runtime_manager: brew-service
                        probe_kind: command
                        oracle:
                          configured: "true"
                          runtime: '[[ -f "{marker}" ]]'
                        evidence:
                          version: "printf 1.2.3"
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        export UCC_RUNTIME_WAIT_ATTEMPTS=20
                        export UCC_RUNTIME_WAIT_INTERVAL=0.01
                        source "{ROOT / 'lib/ucc.sh'}"

                        brew_observe() {{ printf '1.2.3'; }}
                        _ucc_brew_service_status() {{
                          [[ -f "{started}" ]] && printf 'started' || printf 'stopped'
                        }}
                        brew() {{
                          printf '%s\\n' "$*" >> "{commands}"
                          touch "{started}"
                          (
                            sleep 0.05
                            touch "{marker}"
                          ) &
                        }}

                        ucc_brew_runtime_formula_target "fake-service" "fake" "fake-ref" "{ROOT}" "{manifest}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("services start fake-ref", commands.read_text(encoding="utf-8"))
            self.assertIn("[installed] fake-service", result.stdout)

    def test_brew_runtime_formula_target_uses_yaml_probe_and_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            marker = tmp_path / "runtime.ok"
            marker.write_text("ok", encoding="utf-8")
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    f"""\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      fake-app:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake App
                        driver:
                          kind: brew-service
                        runtime_manager: brew-service
                        probe_kind: command
                        oracle:
                          configured: "true"
                          runtime: '[[ -f "{marker}" ]]'
                        evidence:
                          version: "printf 1.2.3"
                          pid: "printf 4321"
                          listener: "printf tcp:127.0.0.1:9999"
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        brew_observe() {{ printf '1.2.3'; }}
                        _ucc_brew_service_status() {{ printf 'started'; }}

                        ucc_brew_runtime_formula_target "fake-app" "fake-app" "fake-ref" "{ROOT}" "{manifest}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("[ok      ] fake-app", result.stdout)
            self.assertIn("version=1.2.3", result.stdout)
            self.assertIn("pid=4321", result.stdout)
            self.assertIn("listener=tcp:127.0.0.1:9999", result.stdout)

    def test_brew_runtime_formula_target_upgrades_outdated_package_and_restarts_service(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            marker = tmp_path / "runtime.ok"
            commands = tmp_path / "commands.txt"
            ucc_dir = self._write_manifest(
                tmp_path,
                textwrap.dedent(
                    f"""\
                    component: fake
                    primary_profile: runtime
                    libs: fake
                    runner: run_fake
                    targets:
                      fake-app:
                        component: fake
                        profile: runtime
                        type: runtime
                        display_name: Fake App
                        driver:
                          kind: brew-service
                        runtime_manager: brew-service
                        probe_kind: command
                        oracle:
                          configured: "true"
                          runtime: '[[ -f "{marker}" ]]'
                        evidence:
                          version: "printf 2.0.0"
                    """
                ),
            )
            manifest = ucc_dir / "software" / "fake.yaml"
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export UCC_DECLARATION_FILE="{tmp_path / 'decl.jsonl'}"
                        export UCC_RESULT_FILE="{tmp_path / 'result.jsonl'}"
                        export UCC_SUMMARY_FILE="{tmp_path / 'summary.txt'}"
                        export UCC_PROFILE_SUMMARY_FILE="{tmp_path / 'profile.txt'}"
                        export UCC_TARGET_STATUS_FILE="{tmp_path / 'status.txt'}"
                        export UCC_CORRELATION_ID="test-run"
                        source "{ROOT / 'lib/ucc.sh'}"

                        brew_observe() {{ [[ -f "{marker}" ]] && printf '2.0.0' || printf 'outdated'; }}
                        _ucc_brew_service_status() {{ printf 'started'; }}
                        brew_install() {{ printf 'install %s\\n' "$*" >> "{commands}"; }}
                        brew_upgrade() {{ printf 'upgrade %s\\n' "$*" >> "{commands}"; touch "{marker}"; }}
                        brew() {{ printf '%s\\n' "$*" >> "{commands}"; touch "{marker}"; }}

                        ucc_brew_runtime_formula_target "fake-app" "fake-app" "fake-ref" "{ROOT}" "{manifest}"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            command_log = commands.read_text(encoding="utf-8")
            self.assertIn("upgrade fake-ref", command_log)
            self.assertIn("services restart fake-ref", command_log)
            self.assertIn("fake-app", result.stdout)

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
                        state_model: config
                        display_name: Config A
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
                      b:
                        component: fake
                        profile: configured
                        type: config
                        state_model: config
                        display_name: Config B
                        depends_on:
                          - a
                        driver:
                          kind: shell-file-edit
                        evidence:
                          state: "printf configured"
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
