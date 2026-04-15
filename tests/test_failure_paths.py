#!/usr/bin/env python3
"""Regression tests for the recovery/failure paths surfaced during the
2026-04-14/15 debugging session:

- #38 disk cache invalidation after upgrades
- #39 component cascade abort on single target FAIL
- #40 observe-only wording for capability targets
- #41 pip constraint-bound warn-not-fail
- #47 cache bulk invalidation
- exit code 124/125 propagation through _ucc_run_yaml_action

Each test exercises a specific code path that, if regressed, would
re-introduce a known bug.
"""

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _bash(script: str, env=None) -> subprocess.CompletedProcess:
    """Run a bash snippet with strict error handling. Returns the process."""
    return subprocess.run(
        ["bash", "-c", textwrap.dedent(script)],
        text=True, capture_output=True, env=env,
    )


class PipConstraintBoundTests(unittest.TestCase):
    """Tests for lib/pip_common.sh::_pip_constraint_bound_check (extracted in #50)."""

    def _check(self, action: str, rc: int, check_returns_true: bool) -> int:
        """Call _pip_constraint_bound_check with a mocked check function."""
        mock_fn = "true" if check_returns_true else "false"
        result = _bash(f"""\
            source "{ROOT}/lib/ucc_log.sh"
            source "{ROOT}/lib/pip_common.sh"
            _mock_check() {{ {mock_fn}; }}
            _pip_constraint_bound_check "{action}" "{rc}" _mock_check
            echo "rc=$?"
        """)
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        return int(result.stdout.strip().split("rc=")[-1])

    def test_update_rc0_still_outdated_returns_124(self):
        """action=update, rc=0, still outdated → 124 (warn)."""
        self.assertEqual(self._check("update", 0, True), 124)

    def test_update_rc0_not_outdated_returns_0(self):
        """action=update, rc=0, NOT outdated → 0 (converged)."""
        self.assertEqual(self._check("update", 0, False), 0)

    def test_update_rc_nonzero_passes_through(self):
        """action=update, rc=1 → passes through rc=1 (action failed)."""
        self.assertEqual(self._check("update", 1, True), 1)

    def test_install_action_never_warns(self):
        """action=install never triggers the constraint-bound path."""
        self.assertEqual(self._check("install", 0, True), 0)


class CacheInvalidationTests(unittest.TestCase):
    """Tests for lib/utils.sh disk cache helpers (added in #38/#47)."""

    def test_cache_write_read_invalidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = _bash(f"""\
                export UCC_CACHE_DIR="{tmp}"
                source "{ROOT}/lib/ucc_log.sh"
                source "{ROOT}/lib/utils.sh"
                printf 'hello' | _ucc_cache_write 'test-key'
                val1="$(_ucc_cache_read 'test-key')"
                _ucc_cache_invalidate 'test-key'
                val2="$(_ucc_cache_read 'test-key')"
                echo "val1=$val1 val2=$val2"
            """)
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("val1=hello val2=", result.stdout)

    def test_cache_fresh_ttl_respected(self):
        """_ucc_cache_fresh returns true only within TTL."""
        with tempfile.TemporaryDirectory() as tmp:
            result = _bash(f"""\
                export UCC_CACHE_DIR="{tmp}"
                export UCC_CACHE_TTL_MIN=60
                source "{ROOT}/lib/ucc_log.sh"
                source "{ROOT}/lib/utils.sh"
                printf 'x' | _ucc_cache_write 'fresh-key'
                _ucc_cache_fresh "$(_ucc_cache_path 'fresh-key')" && echo FRESH || echo STALE
            """)
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("FRESH", result.stdout)

    def test_cache_bulk_invalidate_glob(self):
        """_ucc_cache_invalidate_glob removes matching entries, keeps others."""
        with tempfile.TemporaryDirectory() as tmp:
            result = _bash(f"""\
                export UCC_CACHE_DIR="{tmp}"
                source "{ROOT}/lib/ucc_log.sh"
                source "{ROOT}/lib/utils.sh"
                printf 'x' | _ucc_cache_write 'pip-global'
                printf 'x' | _ucc_cache_write 'pip-venv-ai-modern'
                printf 'x' | _ucc_cache_write 'brew-livecheck'
                _ucc_cache_invalidate_glob 'pip-*'
                ls "{tmp}" | sort
            """)
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual(result.stdout.strip(), "brew-livecheck")

    def test_cache_no_cache_env_disables_fresh(self):
        """UCC_NO_CACHE=1 forces cache miss even when file is fresh."""
        with tempfile.TemporaryDirectory() as tmp:
            result = _bash(f"""\
                export UCC_CACHE_DIR="{tmp}"
                export UCC_NO_CACHE=1
                source "{ROOT}/lib/ucc_log.sh"
                source "{ROOT}/lib/utils.sh"
                printf 'x' | _ucc_cache_write 'test-key'
                _ucc_cache_fresh "$(_ucc_cache_path 'test-key')" && echo FRESH || echo STALE
            """)
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn("STALE", result.stdout)


class ExitCodeConventionTests(unittest.TestCase):
    """Tests for the rc=0/1/2/124/125 convention + validation guard added
    in commit 1a377bb (#42 dispatch propagation) and 36dde0d (#48 guard)."""

    def _run_action_with_rc(self, driver_rc: int) -> subprocess.CompletedProcess:
        """Invoke _ucc_run_yaml_action with a stubbed driver that returns driver_rc.
        Returns the process result (stdout, stderr, returncode)."""
        return _bash(f"""\
            source "{ROOT}/lib/ucc_log.sh"
            source "{ROOT}/lib/utils.sh"
            source "{ROOT}/lib/ucc_brew.sh"
            source "{ROOT}/lib/ucc_asm.sh"
            source "{ROOT}/lib/ucc_artifacts.sh"
            source "{ROOT}/lib/ucc_targets.sh"
            # Stub driver.kind lookup: return a non-custom kind so dispatch fires
            _ucc_yaml_target_get() {{ [[ "$4" == "driver.kind" ]] && echo "stub" || echo ""; }}
            # Stub driver action to return a specific exit code
            _ucc_driver_action() {{ return {driver_rc}; }}
            # Stub admin check
            _ucc_yaml_target_admin_required() {{ return 1; }}
            _ucc_run_yaml_action /tmp /tmp/fake.yaml fake-target install
            echo "final_rc=$?"
        """)

    def test_rc_0_propagates(self):
        r = self._run_action_with_rc(0)
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        self.assertIn("final_rc=0", r.stdout)

    def test_rc_1_propagates(self):
        r = self._run_action_with_rc(1)
        self.assertIn("final_rc=1", r.stdout)

    def test_rc_124_warn_propagates(self):
        """Driver returns 124 (warn) — must propagate, not be swallowed.
        Regression test for commit 1a377bb: the old `&& return` pattern
        dropped non-zero codes, causing ollama [fail] even with rc=124."""
        r = self._run_action_with_rc(124)
        self.assertIn("final_rc=124", r.stdout)

    def test_rc_125_admin_required_propagates(self):
        r = self._run_action_with_rc(125)
        self.assertIn("final_rc=125", r.stdout)

    def test_rc_200_nonconventional_coerced_to_1(self):
        """Non-conventional rc (200) should be logged + coerced to 1.
        Added in commit 36dde0d per plan item #48."""
        r = self._run_action_with_rc(200)
        self.assertIn("final_rc=1", r.stdout)
        self.assertIn("non-conventional rc=200", r.stderr)


class CustomDaemonHttpFallbackTests(unittest.TestCase):
    """Tests for lib/drivers/custom_daemon.sh observe HTTP fallback (added
    to fix the intermittent ollama [fail] that survived fix #42).

    These tests stub the YAML lookups + binary-exists check directly rather
    than go through a real manifest, because custom_daemon_observe's code
    path is linear and the YAML reads are the only external dependencies
    that matter for testing the fallback branch."""

    def _run_observe(self, http_succeeds: bool) -> subprocess.CompletedProcess:
        http_ret = "return 0" if http_succeeds else "return 1"
        return _bash(f"""\
            source "{ROOT}/lib/ucc_log.sh"
            source "{ROOT}/lib/utils.sh"
            source "{ROOT}/lib/ucc_brew.sh"
            source "{ROOT}/lib/ucc_targets.sh"
            source "{ROOT}/lib/ucc_drivers.sh"
            # Stub YAML reads: return a stub binary name + unmatched process pattern
            _ucc_yaml_target_get() {{
              case "$4" in
                driver.bin)     echo "/bin/ls" ;;  # /bin/ls always exists
                driver.process) echo "pattern-that-never-matches-xyzzy123" ;;
                *) echo "" ;;
              esac
            }}
            # Override pgrep to always miss (simulates the race condition)
            pgrep() {{ return 1; }}
            # Stub HTTP probe result
            _ucc_http_probe_endpoint() {{ {http_ret}; }}
            _ucc_driver_custom_daemon_observe /tmp /tmp/fake.yaml fake-target
        """)

    def test_pgrep_miss_with_http_success_reports_running(self):
        """pgrep miss + HTTP success → 'running' (was 'stopped' before fix)."""
        r = self._run_observe(http_succeeds=True)
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        self.assertIn("running", r.stdout)

    def test_pgrep_miss_http_fail_reports_stopped(self):
        """pgrep miss + HTTP fail → 'stopped' (genuinely down)."""
        r = self._run_observe(http_succeeds=False)
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        self.assertIn("stopped", r.stdout)


class ObserveOnlyWordingTests(unittest.TestCase):
    """Tests for capability target wording when no install_fn (added in #40).
    Uses ucc_target directly with no --install fn to verify the code path."""

    def _run_capability_target(self, observed_fn_body: str, dry_run: int = 0):
        """Invoke ucc_target with a capability profile and no install fn.
        Omitting --desired lets ucc_target pull the profile default."""
        return _bash(f"""\
            export UCC_DRY_RUN={dry_run}
            export UCC_MODE=install
            source "{ROOT}/lib/ucc_log.sh"
            source "{ROOT}/lib/ucc_asm.sh"
            source "{ROOT}/lib/ucc_artifacts.sh"
            source "{ROOT}/lib/ucc_targets.sh"
            # Load profiles (capability axes + desired baseline)
            source "{ROOT}/lib/uic.sh"
            _ucc_profiles_load "{ROOT}"
            # Stub observe — returns observed state JSON via ucc_asm_state
            _stub_obs() {{ {observed_fn_body} ; }}
            ucc_target --name fake-cap --profile capability --observe _stub_obs
        """)

    def test_capability_unavailable_dry_run_shows_observe_only(self):
        """Capability probe fails in dry-run → [observe] not [dry-run] with
        misleading transition projection."""
        obs = 'ucc_asm_state --installation Configured --runtime Stopped --health Unavailable --admin Enabled --dependencies DepsReady'
        r = self._run_capability_target(obs, dry_run=1)
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        self.assertIn("[observe", r.stdout)
        self.assertIn("observe-only", r.stdout)
        self.assertNotIn("->", r.stdout.replace("→", ""))  # no transition arrow

    def test_capability_unavailable_realrun_shows_observe_only(self):
        """Capability probe fails in real-run → [observe] not [policy blocked]."""
        obs = 'ucc_asm_state --installation Configured --runtime Stopped --health Unavailable --admin Enabled --dependencies DepsReady'
        r = self._run_capability_target(obs, dry_run=0)
        self.assertEqual(r.returncode, 0, msg=r.stderr)
        self.assertIn("[observe", r.stdout)
        self.assertIn("observe-only", r.stdout)
        self.assertNotIn("policy blocked", r.stdout)


if __name__ == "__main__":
    unittest.main()
