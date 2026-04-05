#!/usr/bin/env python3
"""Test that YAML files contain only configuration, never runtime logic (Rule 8)."""

import os
import glob
import unittest
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Allowed keys per YAML structure type
PREFERENCE_ALLOWED_KEYS = {"name", "default", "options", "rationale", "scope"}
SELECTION_ALLOWED_KEYS = {"default", "disabled"}

# Keys that indicate runtime logic leaked into YAML
RUNTIME_LOGIC_KEYS = {
    "skip_when", "run_if", "run_unless", "skip_if",
    "condition", "when", "unless", "if", "enabled",
}


class YamlSchemaTests(unittest.TestCase):
    """Validate YAML files contain only allowed configuration keys."""

    def _load_yaml(self, path: str) -> dict:
        with open(path) as f:
            return yaml.safe_load(f) or {}

    def test_preferences_only_allowed_keys(self):
        """defaults/preferences.yaml preferences must use only allowed keys."""
        path = os.path.join(REPO_ROOT, "defaults", "preferences.yaml")
        data = self._load_yaml(path)
        for pref in data.get("preferences", []):
            if not isinstance(pref, dict):
                continue
            extra = set(pref.keys()) - PREFERENCE_ALLOWED_KEYS
            self.assertEqual(
                extra, set(),
                f"preference '{pref.get('name', '?')}' has disallowed keys: {extra}"
            )

    def test_preferences_no_runtime_logic_keys(self):
        """No preference should contain runtime logic fields."""
        path = os.path.join(REPO_ROOT, "defaults", "preferences.yaml")
        data = self._load_yaml(path)
        for pref in data.get("preferences", []):
            if not isinstance(pref, dict):
                continue
            leaked = set(pref.keys()) & RUNTIME_LOGIC_KEYS
            self.assertEqual(
                leaked, set(),
                f"preference '{pref.get('name', '?')}' contains runtime logic keys: {leaked}"
            )

    def test_component_preferences_no_runtime_logic(self):
        """Component-level preferences in ucc/ manifests must not have runtime logic keys."""
        yaml_files = (
            glob.glob(os.path.join(REPO_ROOT, "ucc", "software", "*.yaml"))
            + glob.glob(os.path.join(REPO_ROOT, "ucc", "system", "*.yaml"))
        )
        for yf in yaml_files:
            data = self._load_yaml(yf)
            for pref in data.get("preferences", []):
                if not isinstance(pref, dict):
                    continue
                leaked = set(pref.keys()) & RUNTIME_LOGIC_KEYS
                self.assertEqual(
                    leaked, set(),
                    f"{os.path.basename(yf)}: preference '{pref.get('name', '?')}' "
                    f"contains runtime logic keys: {leaked}"
                )
                extra = set(pref.keys()) - PREFERENCE_ALLOWED_KEYS
                self.assertEqual(
                    extra, set(),
                    f"{os.path.basename(yf)}: preference '{pref.get('name', '?')}' "
                    f"has disallowed keys: {extra}"
                )

    def test_selection_only_allowed_keys(self):
        """defaults/selection.yaml must use only allowed top-level keys."""
        path = os.path.join(REPO_ROOT, "defaults", "selection.yaml")
        data = self._load_yaml(path)
        extra = set(data.keys()) - SELECTION_ALLOWED_KEYS
        self.assertEqual(
            extra, set(),
            f"selection.yaml has disallowed top-level keys: {extra}"
        )

    def test_no_runtime_logic_in_target_keys(self):
        """Target definitions must not contain runtime logic keys."""
        yaml_files = (
            glob.glob(os.path.join(REPO_ROOT, "ucc", "software", "*.yaml"))
            + glob.glob(os.path.join(REPO_ROOT, "ucc", "system", "*.yaml"))
        )
        for yf in yaml_files:
            data = self._load_yaml(yf)
            for tname, tdata in (data.get("targets") or {}).items():
                if not isinstance(tdata, dict):
                    continue
                leaked = set(tdata.keys()) & RUNTIME_LOGIC_KEYS
                self.assertEqual(
                    leaked, set(),
                    f"{os.path.basename(yf)}: target '{tname}' "
                    f"contains runtime logic keys: {leaked}"
                )


if __name__ == "__main__":
    unittest.main()
