#!/usr/bin/env python3
"""Test host fingerprint resolution and condition matching."""

import os
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from validate_targets_manifest import (
    _resolve_conditional_dep, _host_match_values, _eval_single_condition,
    _host_named_values, _version_compare,
)


def set_env(**kwargs):
    for k, v in kwargs.items():
        os.environ[k] = v


def test_version_compare():
    """Version comparison works for common cases."""
    assert _version_compare("15.4", ">=", "14") == True
    assert _version_compare("15.4", ">=", "15.4") == True
    assert _version_compare("12.0", ">=", "14") == False
    assert _version_compare("22.04", ">=", "20.04") == True
    assert _version_compare("22.04", "<", "24.04") == True
    assert _version_compare("3.12.3", ">=", "3.11") == True
    assert _version_compare("3.12.3", "==", "3.12.3") == True
    assert _version_compare("3.12.3", "!=", "3.11.9") == True
    print("PASS: Version comparisons work")


def test_simple_condition_match():
    """Simple value matching against host variables."""
    set_env(
        HOST_PLATFORM="macos", HOST_PLATFORM_VARIANT="macos",
        HOST_PACKAGE_MANAGER="brew", HOST_OS_ID="macos-15.4",
        HOST_ARCH="arm64", HOST_FINGERPRINT="macos/15.4/arm64/brew",
    )
    vals = _host_match_values()

    assert _eval_single_condition("macos", vals) == True
    assert _eval_single_condition("linux", vals) == False
    assert _eval_single_condition("brew", vals) == True
    assert _eval_single_condition("apt", vals) == False
    assert _eval_single_condition("arm64", vals) == True
    assert _eval_single_condition("x86_64", vals) == False
    print("PASS: Simple condition matching")


def test_negation():
    """!value negation works."""
    set_env(
        HOST_PLATFORM="macos", HOST_PLATFORM_VARIANT="macos",
        HOST_PACKAGE_MANAGER="brew", HOST_OS_ID="macos-15.4",
        HOST_ARCH="arm64", HOST_FINGERPRINT="macos/15.4/arm64/brew",
    )
    vals = _host_match_values()

    assert _eval_single_condition("!linux", vals) == True
    assert _eval_single_condition("!macos", vals) == False
    assert _eval_single_condition("!brew", vals) == False
    assert _eval_single_condition("!apt", vals) == True
    print("PASS: Negation works")


def test_version_condition():
    """name>=version conditions work."""
    set_env(
        HOST_PLATFORM="macos", HOST_PLATFORM_VARIANT="macos",
        HOST_PACKAGE_MANAGER="brew", HOST_OS_ID="macos-15.4",
        HOST_ARCH="arm64", HOST_FINGERPRINT="macos/15.4/arm64/brew",
    )
    vals = _host_match_values()

    assert _eval_single_condition("macos>=14", vals) == True
    assert _eval_single_condition("macos>=16", vals) == False
    assert _eval_single_condition("macos<16", vals) == True
    assert _eval_single_condition("macos==15.4", vals) == True
    print("PASS: Version conditions work")


def test_or_conditions():
    """Comma-separated OR conditions."""
    # macOS 15.4
    set_env(HOST_PLATFORM="macos", HOST_PLATFORM_VARIANT="macos",
            HOST_PACKAGE_MANAGER="brew", HOST_OS_ID="macos-15.4",
            HOST_FINGERPRINT="macos/15.4/arm64/brew", HOST_ARCH="arm64")
    _, included = _resolve_conditional_dep("dep?macos>=14,linux,wsl2", _host_match_values())
    assert included == True, "macOS 15.4 should match macos>=14"

    # macOS 12.0
    set_env(HOST_OS_ID="macos-12.0", HOST_FINGERPRINT="macos/12.0/arm64/brew")
    _, included = _resolve_conditional_dep("dep?macos>=14,linux,wsl2", _host_match_values())
    assert included == False, "macOS 12.0 should NOT match"

    # Linux
    set_env(HOST_PLATFORM="linux", HOST_PLATFORM_VARIANT="linux",
            HOST_PACKAGE_MANAGER="apt", HOST_OS_ID="ubuntu-22.04",
            HOST_FINGERPRINT="ubuntu/22.04/x86_64/apt", HOST_ARCH="x86_64")
    _, included = _resolve_conditional_dep("dep?macos>=14,linux,wsl2", _host_match_values())
    assert included == True, "Linux should match"

    # WSL2
    set_env(HOST_PLATFORM="wsl", HOST_PLATFORM_VARIANT="wsl2")
    _, included = _resolve_conditional_dep("dep?macos>=14,linux,wsl2", _host_match_values())
    assert included == True, "WSL2 should match"

    print("PASS: OR conditions with mixed types work")


def test_union_mode():
    """host_values=None returns all deps (union mode for validation)."""
    target, included = _resolve_conditional_dep("dep?macos>=14,linux", None)
    assert target == "dep"
    assert included == True, "Union mode should always include"
    print("PASS: Union mode works")


def test_no_condition():
    """No ? means unconditional."""
    target, included = _resolve_conditional_dep("some-target", _host_match_values())
    assert target == "some-target"
    assert included == True
    print("PASS: Unconditional deps always included")


if __name__ == "__main__":
    test_version_compare()
    test_simple_condition_match()
    test_negation()
    test_version_condition()
    test_or_conditions()
    test_union_mode()
    test_no_condition()
    print("\nAll fingerprint/condition tests passed.")
