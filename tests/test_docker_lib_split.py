#!/usr/bin/env python3
"""Pin the 2026-04-28 Docker library split.

Three files now carry Docker code:
  lib/docker_common.sh         — portable helpers + dispatcher
  lib/docker_engine.sh         — Linux/WSL existing-engine support
  lib/docker_desktop_macos.sh  — macOS Docker Desktop app + launch
  lib/docker.sh                — backward-compat loader, sources the three

These tests pin the boundary so future edits don't put macOS-only logic
back into the engine path or vice versa.
"""
import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LIB = REPO / "lib"


class DockerLibSplitTests(unittest.TestCase):
    def test_engine_file_has_no_macos_only_calls(self):
        text = (LIB / "docker_engine.sh").read_text()
        for forbidden in ("osascript", "open -g", "open -a", "xattr",
                          "/Applications", "settings-store", "brew_cask",
                          "_docker_launch"):
            self.assertNotIn(forbidden, text, f"engine file references {forbidden}")

    def test_common_file_has_no_macos_only_calls(self):
        text = (LIB / "docker_common.sh").read_text()
        for forbidden in ("osascript", "open -g", "open -a", "xattr",
                          "/Applications", "brew_cask"):
            self.assertNotIn(forbidden, text, f"common file references {forbidden}")

    def test_macos_file_carries_the_macos_only_funcs(self):
        text = (LIB / "docker_desktop_macos.sh").read_text()
        for fn in ("docker_desktop_observe", "docker_desktop_is_running",
                   "_docker_launch", "_docker_cask_ensure",
                   "_docker_settings_store_patch", "_docker_strip_quarantine",
                   "_docker_bootstrap_complete", "docker_resources_observe",
                   "docker_privileged_ports_observe"):
            self.assertRegex(text, rf"(?m)^{re.escape(fn)}\(\)")

    def test_loader_sources_all_three(self):
        text = (LIB / "docker.sh").read_text()
        for f in ("docker_common.sh", "docker_engine.sh",
                  "docker_desktop_macos.sh"):
            self.assertIn(f, text)

    def test_engine_file_sources_independently(self):
        # docker_engine.sh must be self-contained relative to docker_common.sh
        # + utils.sh. Sourcing in isolation should not error.
        script = (
            "source lib/utils.sh; source lib/docker_common.sh; "
            "source lib/docker_engine.sh; "
            "type _docker_engine_start >/dev/null"
        )
        r = subprocess.run(
            ["bash", "-c", script], cwd=REPO,
            capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)

    def test_engine_start_skips_when_no_init_system(self):
        script = r'''
            source lib/ucc.sh
            source lib/utils.sh
            source lib/docker_common.sh
            source lib/docker_engine.sh
            HOST_PLATFORM=linux
            HOST_FINGERPRINT="ubuntu/22.04/x86_64/apt/no-init-system"
            _docker_ready() { return 1; }
            _docker_engine_start
        '''
        r = subprocess.run(
            ["bash", "-c", script], cwd=REPO,
            capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 125, r.stderr + r.stdout)


if __name__ == "__main__":
    unittest.main()
