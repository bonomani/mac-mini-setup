#!/usr/bin/env python3
"""Regression tests for the narrow cross-platform Docker daemon path.

Linux/WSL support starts with observing or starting an existing Docker Engine.
It intentionally does not install Docker packages or automate Docker Desktop
for Windows/Linux.
"""

import os
import subprocess
import textwrap
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent


def _bash(script: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", "-c", script],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_docker_component_platforms_include_linux_and_wsl2():
    data = yaml.safe_load((REPO_ROOT / "ucc/software/docker.yaml").read_text())
    assert set(data["platforms"]) == {"macos", "linux", "wsl2"}


def test_docker_linux_daemon_depends_on_desktop_only_on_macos():
    data = yaml.safe_load((REPO_ROOT / "ucc/software/docker.yaml").read_text())
    deps = data["targets"]["docker-daemon"]["depends_on"]
    assert "docker-desktop?macos" in deps
    assert "docker-desktop" not in deps


def test_macos_only_docker_targets_are_gated():
    data = yaml.safe_load((REPO_ROOT / "ucc/software/docker.yaml").read_text())
    assert data["targets"]["docker-desktop"]["requires"] == "macos"
    assert data["targets"]["docker-resources"]["requires"] == "macos"
    assert data["targets"]["docker-privileged-ports"]["requires"] == "macos"


def test_docker_socket_path_defaults_by_platform():
    script = textwrap.dedent(
        r"""
        source lib/utils.sh
        HOST_PLATFORM=macos HOME=/Users/example
        test "$(docker_socket_path)" = "/Users/example/.docker/run/docker.sock"
        HOST_PLATFORM=linux HOME=/home/example
        test "$(docker_socket_path)" = "/var/run/docker.sock"
        HOST_PLATFORM=wsl HOME=/home/example
        test "$(docker_socket_path)" = "/var/run/docker.sock"
        UCC_DOCKER_SOCKET=/tmp/custom.sock
        test "$(docker_socket_path)" = "/tmp/custom.sock"
        """
    )
    result = _bash(script)
    assert result.returncode == 0, result.stderr + result.stdout


def test_linux_daemon_start_returns_success_when_already_ready():
    script = textwrap.dedent(
        r"""
        source lib/ucc.sh
        source lib/utils.sh
        source lib/docker.sh
        HOST_PLATFORM=linux
        _docker_ready() { return 0; }
        _docker_daemon_start
        """
    )
    result = _bash(script)
    assert result.returncode == 0, result.stderr + result.stdout


def test_linux_daemon_start_policy_skips_without_start_backend():
    script = textwrap.dedent(
        r"""
        source lib/ucc.sh
        source lib/utils.sh
        source lib/docker.sh
        HOST_PLATFORM=linux
        HOST_FINGERPRINT="ubuntu/22.04/x86_64/apt/no-init-system"
        _docker_ready() { return 1; }
        _docker_daemon_start
        """
    )
    result = _bash(script)
    assert result.returncode == 125, result.stderr + result.stdout
    assert "no supported Docker start backend" in result.stderr + result.stdout
