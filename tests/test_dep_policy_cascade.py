#!/usr/bin/env python3
"""Test that a target whose dep is [policy] (admin-required, rc=125)
gets [skip]+'dependency requires admin' cascade, NOT [fail] or run-anyway.

Regression for the 2026-04-28 oh-my-zsh / cli-zsh case: cli-zsh apt
install needed sudo (non-interactive without cached ticket → rc=125,
emitted as [policy]). oh-my-zsh listed cli-zsh as depends_on but ran
its installer anyway, which then failed with 'Zsh is not installed'."""

import os
import subprocess
import textwrap

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(REPO_ROOT, "lib", "ucc_targets.sh")


def _run_dep_check(dep_status: str) -> tuple[str, int]:
    """Source ucc_targets.sh, stub status lookup + dep listing, then call
    _ucc_check_deps_recursive on a synthetic target."""
    script = textwrap.dedent(f"""
        source "{LIB}" 2>/dev/null || true
        # Override status helpers AFTER sourcing so they win.
        _ucc_target_direct_deps() {{
          [[ "$1" == "dependent" ]] && echo "blocking-dep"
        }}
        _ucc_target_status_value() {{
          [[ "$1" == "blocking-dep" ]] && echo "{dep_status}"
        }}
        _ucc_target_oracle_configured() {{ :; }}
        _ucc_record_target_status() {{ :; }}
        _ucc_display_name() {{ echo "$1"; }}
        export HOST_PLATFORM=wsl
        _ucc_check_deps_recursive dependent
    """)
    res = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    return res.stdout, res.returncode


def test_policy_dep_cascades_to_skip():
    out, rc = _run_dep_check("policy")
    assert rc == 1, f"expected rc=1 (block), got rc={rc}"
    assert "[skip" in out, f"expected [skip] cascade, got: {out!r}"
    assert "requires admin" in out, f"expected admin reason, got: {out!r}"


def test_failed_dep_cascades_to_dep_fail():
    out, rc = _run_dep_check("failed")
    assert rc == 1
    assert "[dep-fail" in out


def test_platform_skipped_dep_cascades_to_skip():
    out, rc = _run_dep_check("platform-skipped")
    assert rc == 1
    assert "[skip" in out
    assert "not applicable" in out


def test_ok_dep_does_not_block():
    out, rc = _run_dep_check("ok")
    # Status non-empty + non-policy/failed/platform-skipped → continue (no block)
    assert rc == 0, f"expected rc=0 (no block), got rc={rc} out={out!r}"


def test_pkg_load_backends_does_not_clobber_caller_name():
    """Regression: _pkg_load_backends used `while read -r name ref` without
    `local`, which silently overwrote the caller's $name (typically the
    target id) and broke status recording for [policy] and [warn] paths.
    The bug manifested as status-file entries like '|policy' (empty key)
    for any cli-* target whose backend list parsed cleanly."""
    pkg_driver = os.path.join(REPO_ROOT, "lib", "drivers", "pkg.sh")
    script = textwrap.dedent(f"""
        # Stub PyYAML interpreter so the python heredoc inside _pkg_load_backends
        # actually runs and emits backend lines.
        python3() {{ command python3 "$@"; }}
        source "{pkg_driver}" 2>/dev/null || true
        # Caller-scope $name simulating _ucc_execute_target's local
        name="cli-zsh"
        # Point at the real cli-tools.yaml so backends actually parse
        cfg_dir="{REPO_ROOT}"
        yaml="ucc/software/cli-tools.yaml"
        _pkg_load_backends "$cfg_dir" "$yaml" "cli-zsh" 2>/dev/null
        echo "$name"
    """)
    res = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    assert res.stdout.strip() == "cli-zsh", \
        f"_pkg_load_backends clobbered caller $name to {res.stdout.strip()!r}"
