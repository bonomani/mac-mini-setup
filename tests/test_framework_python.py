#!/usr/bin/env python3
"""UCC_FRAMEWORK_PYTHON pinning: framework manifest queries must use a
PyYAML-capable interpreter, not whatever python3 the user shell happens
to expose (pyenv shims can be broken or lack PyYAML)."""

import os
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UTILS = os.path.join(REPO_ROOT, "lib", "utils.sh")


def _source_and_echo(env_extra=None) -> tuple[str, int]:
    script = f'source "{UTILS}" >/dev/null 2>&1; echo "$UCC_FRAMEWORK_PYTHON"'
    env = os.environ.copy()
    if env_extra:
        env.update(env_extra)
    res = subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env)
    return res.stdout.strip(), res.returncode


def test_framework_python_resolves_to_yaml_capable_interpreter():
    out, rc = _source_and_echo()
    assert rc == 0
    assert out, "UCC_FRAMEWORK_PYTHON must be set after sourcing utils.sh"
    # Must be able to import yaml — that's the whole point of the pin.
    res = subprocess.run([out, "-c", "import yaml"], capture_output=True)
    assert res.returncode == 0, f"{out} cannot import yaml"


def test_framework_python_respects_user_override():
    out, _ = _source_and_echo(env_extra={"UCC_FRAMEWORK_PYTHON": "/usr/bin/python3"})
    assert out == "/usr/bin/python3"


def test_no_bare_python3_in_query_callsites():
    """All validate_targets_manifest.py / read_config.py callsites must
    use ${UCC_FRAMEWORK_PYTHON:-python3}, not bare python3."""
    import re
    bad = []
    for sub in ("lib", "."):
        d = os.path.join(REPO_ROOT, sub) if sub != "." else REPO_ROOT
        for fname in os.listdir(d):
            if not fname.endswith(".sh"):
                continue
            path = os.path.join(d, fname)
            if not os.path.isfile(path):
                continue
            with open(path) as fh:
                for i, line in enumerate(fh, 1):
                    if re.search(r'(?<!\w)python3 "[^"]*(?:validate_targets_manifest|read_config)\.py"', line):
                        bad.append(f"{path}:{i}: {line.rstrip()}")
                    if re.search(r'(?<!\w)python3 "\$_QUERY_SCRIPT"', line):
                        bad.append(f"{path}:{i}: {line.rstrip()}")
                    if re.search(r'(?<!\w)python3 "\$UCC_TARGETS_QUERY_SCRIPT"', line):
                        bad.append(f"{path}:{i}: {line.rstrip()}")
    assert not bad, "Bare python3 callsites that bypass UCC_FRAMEWORK_PYTHON:\n" + "\n".join(bad)
