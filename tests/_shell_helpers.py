"""Shared subprocess helpers for shell-based tests.

Many test files in this directory grew their own near-identical `_bash`
helpers (run a script through `bash -c` with a clean PATH, capture
stdout+stderr, return rc + combined output). Consolidate to one
implementation so the call shape stays consistent and individual tests
can focus on the script under test.

Usage:
    from _shell_helpers import bash_in_repo

    rc, out = bash_in_repo("source lib/utils.sh; some_fn")
    rc, out = bash_in_repo("...", env={"FOO": "bar"})

REPO is auto-detected as the parent of `tests/`.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def bash_in_repo(
    script: str,
    env: dict[str, str] | None = None,
    timeout: float | None = 30,
) -> tuple[int, str]:
    """Run `bash -c <script>` with `cwd=REPO` and a minimal PATH.

    The default environment carries only PATH=/usr/bin:/bin so tests are
    repeatable across machines. Pass `env={...}` to add (or override)
    individual variables; the caller's keys win over the default PATH.

    Returns (returncode, stdout+stderr).
    """
    full_env = {"PATH": "/usr/bin:/bin", **(env or {})}
    r = subprocess.run(
        ["bash", "-c", script],
        cwd=REPO,
        capture_output=True,
        text=True,
        env=full_env,
        timeout=timeout,
    )
    return r.returncode, r.stdout + r.stderr
