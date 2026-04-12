#!/usr/bin/env python3
"""Unit tests for lib/docker_unattended.sh — the three helpers that
handle password acquisition, SUDO_ASKPASS setup, and cleanup for the
assisted Docker Desktop first-install recipe.

These tests are WSL-runnable — they don't need Docker, a Mac, or sudo.
Everything operates against a mktemp workdir and inspects file perms,
contents, and exit codes.

Does NOT cover (these land in later commits of the Docker unattended
execution plan):
  - _docker_assisted_prewrite_eula (Step 4)
  - _docker_assisted_seed_vmnetd (Step 5)
  - _docker_assisted_install orchestrator (Step 6)
  - End-to-end behavior on a real Mac mini (Checkpoint C)
"""

import os
import stat
import subprocess
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
LIB = REPO_ROOT / "lib" / "docker_unattended.sh"


def _run_bash(script: str, env_extra: dict | None = None) -> subprocess.CompletedProcess:
    """Source lib/docker_unattended.sh (and log_warn from utils.sh) and
    run the given bash script. Returns CompletedProcess."""
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    prelude = textwrap.dedent(f"""\
        set -u
        # log_warn is defined in lib/utils.sh; we only need that one helper.
        log_warn() {{ printf 'WARN: %s\\n' "$*" >&2; }}
        source "{LIB}"
    """)
    return subprocess.run(
        ["bash", "-c", prelude + script],
        capture_output=True,
        text=True,
        env=env,
        timeout=10,
    )


def test_get_password_env_var_path():
    """UCC_SUDO_PASS env var should be read verbatim (no prompt, no
    trimming). Exit 0, stdout is the password."""
    result = _run_bash(
        '_docker_assisted_get_password',
        env_extra={"UCC_SUDO_PASS": "s3cret pass"},
    )
    assert result.returncode == 0, f"stderr={result.stderr!r}"
    assert result.stdout == "s3cret pass", f"got {result.stdout!r}"


def test_get_password_noninteractive_no_env_fails():
    """Non-interactive + no UCC_SUDO_PASS should fail cleanly with rc=2
    and a log_warn message — no prompting, no hang."""
    result = _run_bash(
        '_docker_assisted_get_password',
        env_extra={"UCC_INTERACTIVE": "0", "UCC_SUDO_PASS": ""},
    )
    assert result.returncode == 2, f"expected rc=2, got {result.returncode}; stderr={result.stderr!r}"
    assert "UCC_SUDO_PASS" in result.stderr, f"stderr should mention UCC_SUDO_PASS; got {result.stderr!r}"


def test_setup_askpass_creates_expected_files_with_perms(tmp_path):
    """setup_askpass should: mktemp a workdir, write mode-0600 pass
    file, write mode-0755 askpass.sh, export SUDO_ASKPASS in the
    caller's shell, and set _DOCKER_ASSISTED_WORKDIR to the workdir.

    Critical: the `export SUDO_ASKPASS` must be visible to the caller's
    shell. Command substitution (subshell) would hide it, which is why
    the helper uses a global out-variable instead of stdout."""
    script = textwrap.dedent('''\
        _docker_assisted_setup_askpass "hunter2" || exit 99
        workdir="$_DOCKER_ASSISTED_WORKDIR"
        echo "WORKDIR=$workdir"
        echo "SUDO_ASKPASS=$SUDO_ASKPASS"
        echo "PASS_CONTENT=$(cat "$workdir/pass")"
        stat -c '%a %n' "$workdir" "$workdir/pass" "$workdir/askpass.sh" 2>/dev/null \\
          || stat -f '%Lp %N' "$workdir" "$workdir/pass" "$workdir/askpass.sh"
    ''')
    result = _run_bash(script)
    assert result.returncode == 0, f"stderr={result.stderr!r}"

    lines = {}
    perm_lines = []
    for line in result.stdout.splitlines():
        if "=" in line and not line[0].isdigit():
            k, v = line.split("=", 1)
            lines[k] = v
        else:
            perm_lines.append(line)

    workdir = lines.get("WORKDIR", "")
    assert workdir, f"no WORKDIR in output: {result.stdout!r}"
    assert os.path.isdir(workdir), f"workdir {workdir} not created"

    assert lines.get("SUDO_ASKPASS") == f"{workdir}/askpass.sh", \
        f"SUDO_ASKPASS not exported correctly: {lines!r}"
    assert lines.get("PASS_CONTENT") == "hunter2", \
        f"pass file content wrong: {lines!r}"

    perms = {p.split()[1]: p.split()[0] for p in perm_lines if p}
    assert perms.get(workdir) == "700", f"workdir perms: {perms!r}"
    assert perms.get(f"{workdir}/pass") == "600", f"pass file perms: {perms!r}"
    assert perms.get(f"{workdir}/askpass.sh") == "755", f"askpass.sh perms: {perms!r}"

    # Clean up the real workdir the test created (no EXIT trap inside bash -c).
    import shutil
    shutil.rmtree(workdir, ignore_errors=True)


def test_cleanup_wipes_pass_and_removes_workdir():
    """cleanup should overwrite the pass file with zeros before
    unlinking, then remove the whole workdir, and unset SUDO_ASKPASS."""
    script = textwrap.dedent('''\
        _docker_assisted_setup_askpass "topsecret" || exit 99
        workdir="$_DOCKER_ASSISTED_WORKDIR"
        # Sanity: workdir + files exist before cleanup.
        [[ -d "$workdir" ]] && [[ -f "$workdir/pass" ]] || { echo "PRE-FAIL"; exit 1; }
        _docker_assisted_cleanup "$workdir"
        # After cleanup: workdir gone, SUDO_ASKPASS unset.
        if [[ -e "$workdir" ]]; then echo "WORKDIR_STILL_EXISTS"; exit 2; fi
        if [[ -n "${SUDO_ASKPASS:-}" ]]; then echo "SUDO_ASKPASS_STILL_SET"; exit 3; fi
        echo "CLEANUP_OK"
    ''')
    result = _run_bash(script)
    assert result.returncode == 0, f"stdout={result.stdout!r} stderr={result.stderr!r}"
    assert "CLEANUP_OK" in result.stdout, f"stdout={result.stdout!r}"


def test_cleanup_is_idempotent_on_empty_or_nonexistent():
    """Calling cleanup with an empty string or a path that no longer
    exists should return 0 without error."""
    script = textwrap.dedent('''\
        _docker_assisted_cleanup "" || { echo "FAIL_EMPTY"; exit 1; }
        _docker_assisted_cleanup "/tmp/xyz-docker-assisted-nonexistent-$$" || { echo "FAIL_MISSING"; exit 2; }
        # Double-cleanup: create + cleanup twice
        _docker_assisted_setup_askpass "x" || exit 99
        workdir="$_DOCKER_ASSISTED_WORKDIR"
        _docker_assisted_cleanup "$workdir" || { echo "FAIL_FIRST"; exit 3; }
        _docker_assisted_cleanup "$workdir" || { echo "FAIL_SECOND"; exit 4; }
        echo "IDEMPOTENT_OK"
    ''')
    result = _run_bash(script)
    assert result.returncode == 0, f"stdout={result.stdout!r} stderr={result.stderr!r}"
    assert "IDEMPOTENT_OK" in result.stdout, f"stdout={result.stdout!r}"


def test_prewrite_eula_creates_file_if_missing(tmp_path):
    """prewrite_eula should create the parent dir + settings file when
    neither exists yet (fresh install scenario), and the resulting file
    should contain all three EULA keys with the expected values."""
    settings = tmp_path / "Library" / "Group Containers" / "group.com.docker" / "settings-store.json"
    assert not settings.parent.exists(), "pre-test: parent dir should not exist"

    script = textwrap.dedent(f'''\
        export CFG_DIR="{REPO_ROOT}"
        _docker_assisted_prewrite_eula "{settings}"
    ''')
    result = _run_bash(script)
    assert result.returncode == 0, f"stderr={result.stderr!r}"
    assert settings.exists(), f"settings file not created at {settings}"

    import json
    data = json.loads(settings.read_text())
    assert data.get("LicenseTermsVersion") == 2, f"got {data!r}"
    assert data.get("DisplayedOnboarding") is True, f"got {data!r}"
    assert data.get("ShowInstallScreen") is False, f"got {data!r}"


def test_prewrite_eula_merges_into_existing_file(tmp_path):
    """prewrite_eula should merge the three EULA keys into an existing
    settings file without clobbering unrelated keys (e.g. keys set by
    _docker_settings_store_patch earlier in the same run)."""
    settings = tmp_path / "settings-store.json"
    import json
    pre_existing = {
        "OpenUIOnStartupDisabled": True,  # from _docker_settings_store_patch
        "MemoryMiB": 49152,               # from a prior docker_resources_apply
        "CustomUserKey": "preserve-me",   # operator-set
    }
    settings.write_text(json.dumps(pre_existing))

    script = textwrap.dedent(f'''\
        export CFG_DIR="{REPO_ROOT}"
        _docker_assisted_prewrite_eula "{settings}"
    ''')
    result = _run_bash(script)
    assert result.returncode == 0, f"stderr={result.stderr!r}"

    data = json.loads(settings.read_text())
    # New EULA keys present:
    assert data.get("LicenseTermsVersion") == 2
    assert data.get("DisplayedOnboarding") is True
    assert data.get("ShowInstallScreen") is False
    # Pre-existing keys preserved:
    assert data.get("OpenUIOnStartupDisabled") is True, f"clobbered: {data!r}"
    assert data.get("MemoryMiB") == 49152, f"clobbered: {data!r}"
    assert data.get("CustomUserKey") == "preserve-me", f"clobbered: {data!r}"


def test_prewrite_eula_rejects_empty_path():
    """Empty settings_path should fail cleanly with rc=1 and a log_warn
    message — catches caller bugs rather than silently mkdir-ing ''."""
    script = 'export CFG_DIR="{}"\n_docker_assisted_prewrite_eula ""'.format(REPO_ROOT)
    result = _run_bash(script)
    assert result.returncode == 1, f"expected rc=1, got {result.returncode}; stderr={result.stderr!r}"
    assert "empty settings_path" in result.stderr, f"stderr={result.stderr!r}"


def test_lib_sourced_has_no_side_effects():
    """Sourcing lib/docker_unattended.sh must not touch the filesystem,
    change env vars, or print to stdout/stderr. Sourcing alone should
    be a pure function-definition pass."""
    result = _run_bash("echo SOURCED_CLEAN")
    assert result.returncode == 0
    assert result.stdout.strip() == "SOURCED_CLEAN", \
        f"sourcing produced unexpected output: {result.stdout!r}"
    assert result.stderr == "", \
        f"sourcing produced unexpected stderr: {result.stderr!r}"
