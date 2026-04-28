#!/usr/bin/env python3
"""Test that target/key names with special chars (., @, /) don't break
bash variable name construction in _ucc_user_override_get."""

import os
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(REPO_ROOT, "lib", "ucc_targets.sh")


def _run_override(target: str, key: str, env_extra=None) -> tuple[str, str, int]:
    """Source ucc_targets.sh and call _ucc_user_override_get with given args.
    Returns (stdout, stderr, rc)."""
    script = f'''
set -u
source "{LIB}" 2>/dev/null || true
_ucc_overlay_load_once() {{ :; }}
_UCC_OVERLAY_CACHE=""
_ucc_user_override_get "{target}" "{key}"
'''
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    res = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env)
    return res.stdout, res.stderr, res.returncode


def test_target_with_at_and_slash_no_invalid_var_error():
    _, stderr, _ = _run_override("npm-global-@openai/codex", "driver.kind")
    assert "invalid variable name" not in stderr, stderr


def test_target_with_dot_no_invalid_var_error():
    _, stderr, _ = _run_override("cli-llama.cpp", "driver.kind")
    assert "invalid variable name" not in stderr, stderr


def test_sanitized_env_override_is_read():
    """An env var written with the sanitized name should be picked up."""
    # 'cli-llama.cpp' + 'driver.kind' → cli_llama_cpp + driver_kind
    env_var = "UCC_OVERRIDE__cli_llama_cpp__driver_kind"
    stdout, stderr, rc = _run_override(
        "cli-llama.cpp", "driver.kind",
        env_extra={env_var: "sentinel-value"},
    )
    assert "invalid variable name" not in stderr, stderr
    assert stdout == "sentinel-value", f"stdout={stdout!r}"
    assert rc == 0
