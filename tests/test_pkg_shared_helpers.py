#!/usr/bin/env python3
"""Pin contracts of pkg.sh shared helpers.

After the 2026-04-28 backend split, two helpers stay in lib/drivers/pkg.sh
and lib/drivers/pkg_github.sh respectively because they are consumed
across multiple backends:
  _pkg_version_lt   — used by pkg_curl + pkg_vscode + custom_daemon
  _pkg_github_latest_tag — used by pkg_github, pkg_curl, custom_daemon, nvm

Pin their behavior so future backend changes can't break upstream
consumers via silent semantic drift.
"""
import sys
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _shell_helpers import bash_in_repo  # noqa: E402


def _bash(script: str, env: dict | None = None) -> tuple[int, str]:
    """Pre-source utils.sh + pkg.sh, then run the caller's snippet."""
    return bash_in_repo(
        "source lib/utils.sh; source lib/drivers/pkg.sh; "
        + textwrap.dedent(script),
        env=env,
    )


class VersionLtTests(unittest.TestCase):
    """`_pkg_version_lt installed latest`: rc 0 = installed older."""

    def _lt(self, a: str, b: str) -> int:
        rc, _ = _bash(f'_pkg_version_lt "{a}" "{b}"')
        return rc

    def test_strictly_older(self):
        self.assertEqual(self._lt("1.2.3", "1.2.4"), 0)
        self.assertEqual(self._lt("1.2.3", "2.0.0"), 0)
        self.assertEqual(self._lt("0.9.0", "1.0.0"), 0)

    def test_equal_is_not_older(self):
        self.assertEqual(self._lt("1.2.3", "1.2.3"), 1)

    def test_newer_is_not_older(self):
        self.assertEqual(self._lt("2.0.0", "1.9.9"), 1)
        self.assertEqual(self._lt("1.10.0", "1.9.0"), 1)

    def test_v_prefix_is_tolerated(self):
        self.assertEqual(self._lt("v1.2.3", "1.2.4"), 0)
        self.assertEqual(self._lt("1.2.3", "v1.2.4"), 0)
        self.assertEqual(self._lt("v1.2.3", "v1.2.3"), 1)

    def test_empty_inputs_return_not_older(self):
        self.assertEqual(self._lt("", "1.2.3"), 1)
        self.assertEqual(self._lt("1.2.3", ""), 1)
        self.assertEqual(self._lt("", ""), 1)


class GithubLatestTagCacheTests(unittest.TestCase):
    """`_pkg_github_latest_tag <repo>`: process-cached; '-' marks failure."""

    def test_parses_tag_via_fake_curl(self):
        # Strips leading 'v', returns version string from JSON tag_name.
        script = (
            'set -e\n'
            'tmp=$(mktemp -d); trap \'rm -rf "$tmp"\' EXIT\n'
            'cat > "$tmp/curl" <<SH\n'
            '#!/usr/bin/env bash\n'
            'printf \'{"tag_name":"v9.9.9"}\\n\'\n'
            'SH\n'
            'chmod +x "$tmp/curl"\n'
            'export PATH="$tmp:$PATH"\n'
            'v="$(_pkg_github_latest_tag owner/repo)"\n'
            'test "$v" = "9.9.9"\n'
        )
        rc, out = _bash(script)
        self.assertEqual(rc, 0, out)

    def test_serves_from_preseeded_cache(self):
        # Cache format: "<repo>\t<tag>" lines. Pre-seed the cache and the
        # function must return the cached tag without invoking curl.
        script = (
            'set -e\n'
            'tmp=$(mktemp -d); trap \'rm -rf "$tmp"\' EXIT\n'
            'cat > "$tmp/curl" <<SH\n'
            '#!/usr/bin/env bash\n'
            'echo "FAKE CURL CALLED" >&2; exit 99\n'
            'SH\n'
            'chmod +x "$tmp/curl"\n'
            'export PATH="$tmp:$PATH"\n'
            'export _PKG_GH_TAG_CACHE="owner/repo\t7.7.7"\n'
            'v="$(_pkg_github_latest_tag owner/repo)"\n'
            'test "$v" = "7.7.7"\n'
        )
        rc, out = _bash(script)
        self.assertEqual(rc, 0, out)
        self.assertNotIn("FAKE CURL CALLED", out)

    def test_dash_in_cache_means_lookup_failed(self):
        # Pre-seeded "-" tag → function returns failure without calling curl.
        script = (
            'export _PKG_GH_TAG_CACHE="owner/missing\t-"\n'
            '_pkg_github_latest_tag owner/missing\n'
        )
        rc, _ = _bash(script)
        self.assertEqual(rc, 1)

    def test_empty_repo_returns_failure(self):
        rc, _ = _bash('_pkg_github_latest_tag ""')
        self.assertEqual(rc, 1)


if __name__ == "__main__":
    unittest.main()
