#!/usr/bin/env python3
"""Pin the 2026-04-28 pkg.sh github-backend extraction.

GitHub-release helpers were moved from lib/drivers/pkg.sh into a focused
lib/drivers/pkg_github.sh that pkg.sh sources before backend dispatch.
First slice of the pkg.sh backend split. Future backends (npm, curl,
brew, native_pm, vscode, ollama, pyenv, winget) follow the same pattern.
"""
import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PKG = REPO / "lib/drivers/pkg.sh"
PKG_GH = REPO / "lib/drivers/pkg_github.sh"


class PkgGithubSplitTests(unittest.TestCase):
    def test_pkg_github_file_carries_the_github_funcs(self):
        text = PKG_GH.read_text()
        for fn in ("_pkg_github_decode", "_pkg_github_field",
                   "_pkg_github_os", "_pkg_github_arch", "_pkg_github_arch_alt",
                   "_pkg_github_bin_dir", "_pkg_github_state_dir",
                   "_pkg_github_template", "_pkg_github_available",
                   "_pkg_github_activate", "_pkg_github_observe",
                   "_pkg_github_install", "_pkg_github_update",
                   "_pkg_github_version", "_pkg_github_outdated",
                   "_pkg_github_latest_tag"):
            self.assertRegex(text, rf"(?m)^{re.escape(fn)}\(\)")

    def test_pkg_sh_no_longer_defines_github_funcs(self):
        text = PKG.read_text()
        for fn in ("_pkg_github_decode", "_pkg_github_install",
                   "_pkg_github_latest_tag"):
            self.assertNotRegex(text, rf"(?m)^{re.escape(fn)}\(\)")

    def test_pkg_sh_sources_pkg_github(self):
        text = PKG.read_text()
        self.assertIn("pkg_github.sh", text)

    def test_funcs_are_available_after_sourcing_pkg_sh(self):
        # Sourcing pkg.sh must transitively pull in the github backend
        # so existing call sites in custom_daemon.sh / nvm.sh keep working.
        script = (
            "source lib/utils.sh; source lib/drivers/pkg.sh; "
            "declare -f _pkg_github_install >/dev/null && "
            "declare -f _pkg_github_latest_tag >/dev/null"
        )
        r = subprocess.run(
            ["bash", "-c", script], cwd=REPO,
            capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)


if __name__ == "__main__":
    unittest.main()
