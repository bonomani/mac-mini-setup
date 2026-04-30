"""Verify install.sh's _ucc_sudo_probe sets _UCC_SUDO_AVAILABLE correctly.

Mirrors the operator's empirical check:

    sudo -k; sudo -v && sudo -n true; echo "rc=$?"   # rc=0 on a healthy host

Stubs `sudo` so we can assert each branch without touching real sudo.
"""
from __future__ import annotations

import unittest

from _shell_helpers import bash_in_repo


def _extract_probe() -> str:
    """Pull `_ucc_sudo_probe` out of install.sh as a sourceable snippet."""
    import re
    from pathlib import Path

    src = Path(__file__).resolve().parent.parent / "install.sh"
    text = src.read_text()
    m = re.search(r"_ucc_sudo_probe\(\) \{.*?\n\}\n", text, re.DOTALL)
    assert m, "could not locate _ucc_sudo_probe in install.sh"
    return m.group(0)


PROBE = _extract_probe()


def _run(stub_body: str) -> tuple[int, str]:
    script = (
        "set -u\n"
        'd=$(mktemp -d)\n'
        'printf "%s\\n" "#!/bin/bash" ' + repr(stub_body) + ' >"$d/sudo"\n'
        'chmod +x "$d/sudo"\n'
        'export PATH="$d:$PATH"\n'
        + PROBE +
        '_ucc_sudo_probe\n'
        'echo "FLAG=${_UCC_SUDO_AVAILABLE:-unset}"\n'
    )
    return bash_in_repo(script)


class SudoProbeTests(unittest.TestCase):
    def test_silent_ok_sets_flag_one(self):
        # `sudo -n true` succeeds → flag=1 without touching tty fallback.
        rc, out = _run('[[ "$1" == "-n" && "$2" == "true" ]] && exit 0; exit 1')
        self.assertEqual(rc, 0, out)
        self.assertIn("FLAG=1", out)

    def test_silent_fail_no_tty_sets_flag_zero(self):
        # `sudo -n true` fails and no /dev/tty in the test env → flag=0.
        # bash_in_repo runs under subprocess.run without a tty, so the
        # `[[ -c /dev/tty ]]` branch is also false.
        rc, out = _run("exit 1")
        self.assertEqual(rc, 0, out)
        self.assertIn("FLAG=0", out)
