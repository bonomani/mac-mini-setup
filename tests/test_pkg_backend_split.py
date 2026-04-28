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


class PkgFullSplitTests(unittest.TestCase):
    """Slices 2-9 (npm, curl, brew, native_pm, winget, pyenv, ollama, vscode).

    Each backend file holds its own funcs and pkg.sh sources it before
    dispatch.
    """

    BACKENDS = {
        "pkg_npm.sh": ["_pkg_npm_observe", "_pkg_npm_install", "_pkg_npm_outdated"],
        "pkg_curl.sh": ["_pkg_curl_install", "_pkg_curl_outdated"],
        "pkg_brew.sh": ["_pkg_brew_install", "_pkg_brew_cask_install"],
        "pkg_native_pm.sh": ["_pkg_native_pm_observe", "_pkg_native_pm_install"],
        "pkg_winget.sh": ["_pkg_winget_observe", "_pkg_winget_install"],
        "pkg_pyenv.sh": ["_pkg_pyenv_install", "_pkg_pyenv_observe"],
        "pkg_ollama.sh": ["_pkg_ollama_install", "_pkg_ollama_observe"],
        "pkg_vscode.sh": ["_pkg_vscode_install", "_pkg_vscode_outdated"],
    }

    def test_each_backend_file_carries_its_funcs(self):
        for filename, fns in self.BACKENDS.items():
            text = (REPO / "lib/drivers" / filename).read_text()
            for fn in fns:
                self.assertRegex(text, rf"(?m)^{re.escape(fn)}",
                                 f"{filename} missing {fn}")

    def test_pkg_sh_sources_every_backend(self):
        text = PKG.read_text()
        for filename in self.BACKENDS:
            self.assertIn(filename, text, f"pkg.sh missing source of {filename}")

    def test_pkg_sh_dispatcher_only(self):
        # Dispatcher should be far smaller than the original 729 LOC.
        self.assertLess(len(PKG.read_text().splitlines()), 300)

    def test_version_lt_remains_in_pkg_sh(self):
        # Shared by curl + vscode backends; stays in the dispatcher file.
        self.assertRegex(PKG.read_text(), r"(?m)^_pkg_version_lt\(\)")


if __name__ == "__main__":
    unittest.main()
