#!/usr/bin/env python3
"""Test that the winget pkg backend maps "no package found" to rc=125
(admin/availability required) instead of rc=1 (fail). This way packages
that aren't on the host's configured winget sources show as [policy]
in the run summary, not as FAILED."""

import os
import subprocess
import textwrap

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PKG_DRIVER = os.path.join(REPO_ROOT, "lib", "drivers", "pkg.sh")


def _run_with_fake_winget(install_rc: int, install_output: str, action: str = "install") -> int:
    """Source pkg.sh with a fake winget shim and call _pkg_winget_install/update."""
    # Heredoc with controlled rc + output, written to a temp shim
    script = textwrap.dedent(f"""
        set -u
        TMP=$(mktemp -d)
        cat > "$TMP/winget" <<'SHIM'
#!/usr/bin/env bash
cat <<'OUT'
{install_output}
OUT
exit {install_rc}
SHIM
        chmod +x "$TMP/winget"
        export PATH="$TMP:$PATH"
        # Stub framework helpers we don't want to pull in.
        log_warn() {{ echo "WARN: $*" >&2; }}
        log_info() {{ echo "INFO: $*" >&2; }}
        ucc_run() {{ "$@"; }}
        # Source just the winget portion by sourcing the whole driver in a
        # forgiving way (other helpers stay unused).
        source "{PKG_DRIVER}" 2>/dev/null || true
        _pkg_winget_{action} VMware.WorkstationPro >/dev/null 2>&1
        rc=$?
        rm -rf "$TMP"
        exit $rc
    """)
    res = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
    return res.returncode


def test_winget_install_rc20_maps_to_125():
    rc = _run_with_fake_winget(20, "Aucun package ne correspond aux critères sélectionnés.")
    assert rc == 125, f"expected 125 (policy), got {rc}"


def test_winget_install_no_match_english_maps_to_125():
    rc = _run_with_fake_winget(1, "No package found matching input criteria.")
    assert rc == 125, f"expected 125 (policy), got {rc}"


def test_winget_install_real_failure_stays_1():
    rc = _run_with_fake_winget(5, "Some other winget error.")
    assert rc == 1, f"expected 1 (fail), got {rc}"


def test_winget_update_rc20_maps_to_125():
    rc = _run_with_fake_winget(20, "Aucun package installé ne correspond.", action="update")
    assert rc == 125, f"expected 125 (policy), got {rc}"
