#!/usr/bin/env python3
"""Pin behavioral contracts of small lib/utils.sh helpers.

These helpers were extracted in items #44, #59, #60, #61 to remove
duplication across drivers. They had no direct unit tests until now;
indirect coverage came from drivers. This file pins their public
contracts so refactors can't silently change semantics.
"""
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def _bash(script: str, env: dict | None = None) -> tuple[int, str]:
    r = subprocess.run(
        ["bash", "-c", script],
        capture_output=True, text=True, cwd=REPO,
        env={"PATH": "/usr/bin:/bin", **(env or {})},
    )
    return r.returncode, r.stdout + r.stderr


class CurlTimeoutTests(unittest.TestCase):
    def test_default_categories(self):
        rc, out = _bash(
            'source lib/utils.sh; '
            'for c in probe endpoint metadata download; do '
            '  printf "%s=%s\\n" "$c" "$(_ucc_curl_timeout "$c")"; '
            'done'
        )
        self.assertEqual(rc, 0, out)
        self.assertIn("probe=5", out)
        self.assertIn("endpoint=10", out)
        self.assertIn("metadata=30", out)
        self.assertIn("download=300", out)

    def test_unknown_category_falls_back_to_probe_default(self):
        rc, out = _bash('source lib/utils.sh; _ucc_curl_timeout bogus')
        self.assertEqual(rc, 0, out)
        self.assertEqual(out.strip(), "5")

    def test_per_category_env_override(self):
        rc, out = _bash(
            'source lib/utils.sh; _ucc_curl_timeout probe',
            env={"UCC_CURL_TIMEOUT_PROBE": "42"},
        )
        self.assertEqual(out.strip(), "42")


class ParseVersionTests(unittest.TestCase):
    def test_extracts_first_dotted_int(self):
        rc, out = _bash(
            'source lib/utils.sh; printf "ollama version 0.20.7 (build abc)\\n" '
            '| _ucc_parse_version'
        )
        self.assertEqual(rc, 0, out)
        self.assertEqual(out, "0.20.7")

    def test_handles_four_segments(self):
        rc, out = _bash(
            'source lib/utils.sh; printf "v1.2.3.4\\n" | _ucc_parse_version'
        )
        self.assertEqual(out, "1.2.3.4")

    def test_returns_1_when_no_match(self):
        rc, _ = _bash(
            'source lib/utils.sh; printf "no digits here\\n" | _ucc_parse_version'
        )
        self.assertEqual(rc, 1)


class WaitUntilTests(unittest.TestCase):
    def test_returns_0_when_cmd_succeeds_immediately(self):
        rc, _ = _bash('source lib/utils.sh; _ucc_wait_until 2 0.1 true')
        self.assertEqual(rc, 0)

    def test_returns_1_on_timeout(self):
        rc, _ = _bash('source lib/utils.sh; _ucc_wait_until 1 0.1 false')
        self.assertEqual(rc, 1)

    def test_succeeds_after_marker_appears(self):
        rc, _ = _bash(r'''
            source lib/utils.sh
            tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
            ( sleep 0.3; touch "$tmp/marker" ) &
            _ucc_wait_until 3 0.1 test -f "$tmp/marker"
        ''')
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
