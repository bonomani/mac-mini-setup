#!/usr/bin/env python3
"""Pin the UCC_NETWORK_PROBE_URL override contract.

The probe URL was previously hardcoded to https://github.com in
network_is_available. Audit item #72 (move policy literals out of
shell). This test verifies the env override is honored AND that the
default still works when unset.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _shell_helpers import bash_in_repo as _bash  # noqa: E402


class NetworkProbeOverrideTests(unittest.TestCase):
    def test_override_url_is_used(self):
        """When UCC_NETWORK_PROBE_URL points to a fake curl that records
        its arg, network_is_available must call it with the override URL."""
        script = r'''
set -e
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/curl" <<'SH'
#!/usr/bin/env bash
# Record args to a marker file; pass-through success.
for a in "$@"; do printf '%s\n' "$a"; done > "$RECORD"
exit 0
SH
chmod +x "$tmp/curl"
export PATH="$tmp:$PATH"
export RECORD="$tmp/args"
export UCC_NETWORK_PROBE_URL="https://example.invalid/ping"
source lib/utils.sh
network_is_available
grep -F 'https://example.invalid/ping' "$RECORD"
'''
        rc, out = _bash(script)
        self.assertEqual(rc, 0, out)

    def test_github_api_base_override_is_used_by_latest_tag_helper(self):
        """GitHub release lookups use the shared API URL builder."""
        script = r'''
set -e
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/curl" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do printf '%s\n' "$a"; done > "$RECORD"
printf '{"tag_name":"v1.2.3"}\n'
exit 0
SH
chmod +x "$tmp/curl"
export PATH="$tmp:$PATH"
export RECORD="$tmp/args"
export UCC_GITHUB_API_BASE_URL="https://github-api.example.test"
source lib/utils.sh
source lib/drivers/pkg.sh
test "$(_pkg_github_latest_tag owner/repo)" = "1.2.3"
grep -F 'https://github-api.example.test/repos/owner/repo/releases/latest' "$RECORD"
'''
        rc, out = _bash(script)
        self.assertEqual(rc, 0, out)

    def test_github_web_base_override_builds_release_download_url(self):
        """The release download URL is built from the shared web base helper."""
        script = r'''
set -e
export UCC_GITHUB_WEB_BASE_URL="https://github-web.example.test/root/"
source lib/utils.sh
test "$(_ucc_github_web_url owner/repo/releases/download/v1/tool)" = \
  "https://github-web.example.test/root/owner/repo/releases/download/v1/tool"
'''
        rc, out = _bash(script)
        self.assertEqual(rc, 0, out)

    def test_default_url_when_unset(self):
        """Without override, default URL is github.com."""
        script = r'''
set -e
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/curl" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do printf '%s\n' "$a"; done > "$RECORD"
exit 0
SH
chmod +x "$tmp/curl"
export PATH="$tmp:$PATH"
export RECORD="$tmp/args"
unset UCC_NETWORK_PROBE_URL
source lib/utils.sh
network_is_available
grep -F 'https://github.com' "$RECORD"
'''
        rc, out = _bash(script)
        self.assertEqual(rc, 0, out)


if __name__ == "__main__":
    unittest.main()
