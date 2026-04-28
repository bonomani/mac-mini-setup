#!/usr/bin/env python3
"""Pin the 2026-04-28 ucc_targets.sh first-slice split.

`lib/ucc_targets.sh` was the largest remaining shell hotspot (1838 LOC).
Slice 1 extracted the YAML target-field reader + user-override layer
into `lib/ucc_targets_yaml.sh` (sourced from ucc_targets.sh near the
top so all downstream lifecycle functions still resolve their helpers).
Mechanical move only — no behavior change.
"""
import re
import subprocess
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TGT = REPO / "lib/ucc_targets.sh"
TGT_YAML = REPO / "lib/ucc_targets_yaml.sh"

YAML_FUNCS = (
    "_ucc_ytgt_source",
    "_ucc_overlay_load_once",
    "_ucc_user_override_get",
    "_ucc_user_override_list",
    "_ucc_yaml_target_get",
    "_ucc_yaml_target_get_many",
    "_ucc_yaml_target_driver_get",
    "_ucc_yaml_target_action_get",
    "_ucc_yaml_target_admin_required",
    "_ucc_eval_yaml_expr",
    "_ucc_yaml_expr_succeeds",
    "_ucc_eval_yaml_scalar_cmd",
)


class UccTargetsSplitTests(unittest.TestCase):
    def test_yaml_file_carries_the_reader_helpers(self):
        text = TGT_YAML.read_text()
        for fn in YAML_FUNCS:
            self.assertRegex(text, rf"(?m)^{re.escape(fn)}\(\)",
                             f"ucc_targets_yaml.sh missing {fn}")

    def test_lifecycle_file_no_longer_defines_them(self):
        text = TGT.read_text()
        for fn in YAML_FUNCS:
            self.assertNotRegex(text, rf"(?m)^{re.escape(fn)}\(\)",
                                f"ucc_targets.sh still defines {fn}")

    def test_lifecycle_file_sources_the_yaml_reader(self):
        self.assertIn("ucc_targets_yaml.sh", TGT.read_text())

    def test_helpers_resolvable_after_sourcing_ucc(self):
        # Sourcing ucc.sh must transitively pull in every reader helper
        # so the lifecycle code that calls them keeps working unchanged.
        check = "; ".join(
            f"declare -f {fn} >/dev/null" for fn in YAML_FUNCS
        )
        r = subprocess.run(
            ["bash", "-c", f"source lib/ucc.sh; {check}"],
            cwd=REPO, capture_output=True, text=True,
        )
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)


if __name__ == "__main__":
    unittest.main()
