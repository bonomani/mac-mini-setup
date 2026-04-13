from __future__ import annotations

import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(
    os.uname().sysname == "Darwin",
    "VS Code settings test requires macOS (code CLI + UCC framework)"
)
class VsCodeSettingsTargetTests(unittest.TestCase):
    def test_vscode_settings_merge_and_observe(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            cfg_dir = tmp_path / "cfg"
            (cfg_dir / "ucc" / "software").mkdir(parents=True)
            (cfg_dir / "scripts").mkdir(parents=True)
            (cfg_dir / "ucc" / "software" / "vscode-settings.json").write_text(
                textwrap.dedent(
                    """\
                    {
                      "editor.inlineSuggest.enabled": true,
                      "extensions.autoUpdate": true,
                      "update.mode": "default"
                    }
                    """
                ),
                encoding="utf-8",
            )
            home_dir = tmp_path / "home"
            settings_dir = home_dir / "Library" / "Application Support" / "Code" / "User"
            settings_dir.mkdir(parents=True)
            settings_file = settings_dir / "settings.json"
            settings_file.write_text(
                textwrap.dedent(
                    """\
                    {
                      "window.zoomLevel": 1
                    }
                    """
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    "bash",
                    "-lc",
                    textwrap.dedent(
                        f"""\
                        set -euo pipefail
                        export HOME="{home_dir}"
                        source "{ROOT / 'lib/ucc.sh'}"
                        source "{ROOT / 'lib/dev_tools.sh'}"
                        cfg_dir="{cfg_dir}"
                        _vscode_settings_match_patch() {{
                          local settings_file="$1" patch_file="$2"
                          python3 - "$settings_file" "$patch_file" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
patch_path = Path(sys.argv[2])

try:
    settings = json.loads(settings_path.read_text())
    patch = json.loads(patch_path.read_text())
except Exception:
    raise SystemExit(1)

if not isinstance(settings, dict) or not isinstance(patch, dict):
    raise SystemExit(1)

for key, value in patch.items():
    if settings.get(key) != value:
        raise SystemExit(1)

raise SystemExit(0)
PY
                        }}
                        _observe_vscode_settings() {{
                          local f="$HOME/Library/Application Support/Code/User/settings.json"
                          local patch_file="$cfg_dir/ucc/software/vscode-settings.json"
                          [[ -f "$f" ]] || {{ ucc_asm_config_state "absent"; return; }}
                          if _vscode_settings_match_patch "$f" "$patch_file"; then
                            ucc_asm_config_state "configured"
                          else
                            ucc_asm_config_state "needs-update"
                          fi
                        }}
                        _apply_vscode_settings() {{
                          local f="$HOME/Library/Application Support/Code/User/settings.json"
                          local patch_file="$cfg_dir/ucc/software/vscode-settings.json"
                          mkdir -p "$(dirname "$f")"
                          local tmp
                          tmp="$(mktemp)"
                          python3 - "$f" "$patch_file" "$tmp" <<'PY'
import json
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
patch_path = Path(sys.argv[2])
tmp_path = Path(sys.argv[3])

patch = json.loads(patch_path.read_text())
if settings_path.exists():
    try:
        settings = json.loads(settings_path.read_text())
    except Exception:
        settings = {{}}
else:
    settings = {{}}
if not isinstance(settings, dict):
    settings = {{}}
settings.update(patch)
tmp_path.write_text(json.dumps(settings, indent=2, sort_keys=True) + "\\n")
PY
                          mv "$tmp" "$f"
                        }}
                        before="$(_observe_vscode_settings)"
                        _apply_vscode_settings
                        after="$(_observe_vscode_settings)"
                        printf 'BEFORE=%s\nAFTER=%s\n' "$before" "$after"
                        cat "$HOME/Library/Application Support/Code/User/settings.json"
                        """
                    ),
                ],
                text=True,
                capture_output=True,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertIn('"health_state":"Degraded"', result.stdout)
            self.assertIn('"health_state":"Healthy"', result.stdout)
            merged = settings_file.read_text(encoding="utf-8")
            self.assertIn('"window.zoomLevel": 1', merged)
            self.assertIn('"editor.inlineSuggest.enabled": true', merged)
            self.assertIn('"extensions.autoUpdate": true', merged)


if __name__ == "__main__":
    unittest.main()
