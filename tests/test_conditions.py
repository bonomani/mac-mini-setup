#!/usr/bin/env python3
"""Test requires: and depends_on?condition resolution."""

import os
import sys
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUERY_SCRIPT = os.path.join(REPO_ROOT, "tools", "validate_targets_manifest.py")
UCC_DIR = os.path.join(REPO_ROOT, "ucc")


def run_query(*args, env_extra=None):
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    result = subprocess.run(
        ["python3", QUERY_SCRIPT] + list(args) + [UCC_DIR],
        capture_output=True, text=True, env=env
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode


MACOS_ENV = {
    "HOST_PLATFORM": "macos", "HOST_PLATFORM_VARIANT": "macos",
    "HOST_PACKAGE_MANAGER": "brew", "HOST_OS_ID": "macos-15.4",
    "HOST_ARCH": "arm64", "HOST_FINGERPRINT": "macos/15.4/arm64/brew",
}

LINUX_ENV = {
    "HOST_PLATFORM": "linux", "HOST_PLATFORM_VARIANT": "linux",
    "HOST_PACKAGE_MANAGER": "apt", "HOST_OS_ID": "ubuntu-22.04",
    "HOST_ARCH": "x86_64", "HOST_FINGERPRINT": "ubuntu/22.04/x86_64/apt",
}

WSL2_ENV = {
    "HOST_PLATFORM": "wsl", "HOST_PLATFORM_VARIANT": "wsl2",
    "HOST_PACKAGE_MANAGER": "apt", "HOST_OS_ID": "ubuntu-22.04",
    "HOST_ARCH": "x86_64", "HOST_FINGERPRINT": "wsl2-ubuntu/22.04/x86_64/apt@windows-11",
}

OLD_MACOS_ENV = {
    "HOST_PLATFORM": "macos", "HOST_PLATFORM_VARIANT": "macos",
    "HOST_PACKAGE_MANAGER": "brew", "HOST_OS_ID": "macos-12.0",
    "HOST_ARCH": "arm64", "HOST_FINGERPRINT": "macos/12.0/arm64/brew",
}


# ── Conditional depends_on tests ──────────────────────────────────────────────

def test_conditional_dep_macos_only():
    """xcode-command-line-tools?macos should only appear on macOS."""
    macos_deps, _, _ = run_query("--dep-targets", "homebrew", env_extra=MACOS_ENV)
    linux_deps, _, _ = run_query("--dep-targets", "homebrew", env_extra=LINUX_ENV)

    assert "xcode-command-line-tools" in macos_deps, \
        f"macOS should include xcode-clt in homebrew deps"
    assert "xcode-command-line-tools" not in linux_deps, \
        f"Linux should NOT include xcode-clt in homebrew deps"
    print("PASS: ?macos conditional dep works")


def test_conditional_dep_not_brew():
    """build-deps?!brew should appear on Linux but not macOS."""
    macos_deps, _, _ = run_query("--dep-targets", "homebrew", env_extra=MACOS_ENV)
    linux_deps, _, _ = run_query("--dep-targets", "homebrew", env_extra=LINUX_ENV)

    assert "build-deps" not in macos_deps, \
        f"macOS (brew) should NOT include build-deps"
    assert "build-deps" in linux_deps, \
        f"Linux (apt) should include build-deps"
    print("PASS: ?!brew conditional dep works")


def test_conditional_dep_version():
    """ollama?macos>=14 should work on macOS 15 but not macOS 12."""
    # ollama has requires: macos>=14,linux,wsl2 — but that's on the target, not deps
    # Let's test the Python resolver directly
    sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
    from validate_targets_manifest import _resolve_conditional_dep, _host_match_values

    # macOS 15.4
    os.environ.update(MACOS_ENV)
    target, included = _resolve_conditional_dep("dep?macos>=14", _host_match_values())
    assert included, f"macOS 15.4 >= 14 should be True"

    # macOS 12.0
    os.environ.update(OLD_MACOS_ENV)
    target, included = _resolve_conditional_dep("dep?macos>=14", _host_match_values())
    assert not included, f"macOS 12.0 >= 14 should be False"

    print("PASS: Version comparison in conditions works")


def test_conditional_dep_or():
    """macos>=14,linux,wsl2 should match macOS, Linux, AND WSL2."""
    sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
    from validate_targets_manifest import _resolve_conditional_dep, _host_match_values

    for name, env, expected in [
        ("macOS 15", MACOS_ENV, True),
        ("macOS 12", OLD_MACOS_ENV, False),
        ("Linux", LINUX_ENV, True),
        ("WSL2", WSL2_ENV, True),
    ]:
        os.environ.update(env)
        _, included = _resolve_conditional_dep("dep?macos>=14,linux,wsl2", _host_match_values())
        assert included == expected, f"{name}: expected {expected}, got {included}"

    print("PASS: OR conditions with version comparison work")


# ── Platform-specific dep chain tests ─────────────────────────────────────────

def test_platform_specific_dep_chains():
    """Dep chains differ by platform."""
    # On macOS: homebrew → xcode-clt + network-available
    macos_deps, _, _ = run_query("--dep-targets", "homebrew", env_extra=MACOS_ENV)
    macos_list = macos_deps.splitlines()
    assert "xcode-command-line-tools" in macos_list
    assert "network-available" in macos_list
    assert "build-deps" not in macos_list

    # On Linux: homebrew → build-deps + network-available
    linux_deps, _, _ = run_query("--dep-targets", "homebrew", env_extra=LINUX_ENV)
    linux_list = linux_deps.splitlines()
    assert "build-deps" in linux_list
    assert "network-available" in linux_list
    assert "xcode-command-line-tools" not in linux_list

    print("PASS: Platform-specific dep chains are correct")


if __name__ == "__main__":
    test_conditional_dep_macos_only()
    test_conditional_dep_not_brew()
    test_conditional_dep_version()
    test_conditional_dep_or()
    test_platform_specific_dep_chains()
    print("\nAll condition tests passed.")
