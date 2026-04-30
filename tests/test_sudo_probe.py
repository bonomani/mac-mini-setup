"""Verify install.sh's _ucc_sudo_probe sets _UCC_SUDO_AVAILABLE correctly.

Mirrors the operator's empirical check:

    sudo -k; sudo -v && sudo -n true; echo "rc=$?"   # rc=0 on a healthy host

Stubs `sudo` so we can assert each branch without touching real sudo,
and records `sudo -v` invocations in a marker file so we can prove the
non-interactive gate prevents prompts.
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


# Stub that fails `sudo -n true` and records every other invocation
# (e.g. `sudo -v`) into $MARKER. Must be a single-line bash body.
RECORDING_STUB = (
    '[[ "$1" == "-n" && "$2" == "true" ]] && exit 1; '
    'printf "%s\\n" "$*" >>"$MARKER"; exit 0'
)


def _run(stub_body: str, env_extra: dict[str, str] | None = None) -> tuple[int, str]:
    script = (
        "set -u\n"
        'd=$(mktemp -d)\n'
        'export MARKER="$d/sudo.calls"\n'
        ': >"$MARKER"\n'
        'printf "%s\\n" "#!/bin/bash" ' + repr(stub_body) + ' >"$d/sudo"\n'
        'chmod +x "$d/sudo"\n'
        'export PATH="$d:$PATH"\n'
        + PROBE +
        '_ucc_sudo_probe\n'
        'echo "FLAG=${_UCC_SUDO_AVAILABLE:-unset}"\n'
        'echo "CALLS=$(wc -l <"$MARKER" | tr -d " ")"\n'
        'cat "$MARKER"\n'
    )
    env = env_extra or {}
    return bash_in_repo(script, env=env)


class SudoProbeTests(unittest.TestCase):
    def test_silent_ok_sets_flag_one(self):
        # `sudo -n true` succeeds → flag=1 without touching tty fallback.
        rc, out = _run('[[ "$1" == "-n" && "$2" == "true" ]] && exit 0; exit 1')
        self.assertEqual(rc, 0, out)
        self.assertIn("FLAG=1", out)

    def test_no_interactive_skips_tty_prompt(self):
        # Silent probe fails. Without UCC_INTERACTIVE=1 the probe MUST NOT
        # invoke `sudo -v` (would prompt the operator). Flag stays 0.
        rc, out = _run(RECORDING_STUB)
        self.assertEqual(rc, 0, out)
        self.assertIn("FLAG=0", out)
        self.assertIn("CALLS=0", out)

